import XCTest
@testable import Dyktando

/// Odpowiedzi HTTP podstawiane zamiast sieci (żadnych prawdziwych zapytań do dostawców).
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(status: Int, body: String, headers: [String: String])] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {  // URLSession przenosi body do strumienia
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            req.httpBody = data
        }
        Self.requests.append(req)
        let next = Self.responses.isEmpty ? (200, "{}", [:]) : Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: next.2)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class MeetingAITests: XCTestCase {
    override func setUp() {
        StubURLProtocol.responses = []
        StubURLProtocol.requests = []
    }

    private func config(_ p: AIProviderID, model: String = "m-1") -> LLMConfig {
        LLMConfig(provider: p, apiKey: "sk-test", model: model, baseURL: p.defaultBaseURL)
    }

    private func body(_ r: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as? [String: Any])
    }

    // MARK: Budowa zapytań

    func test_openAIRequest() throws {
        let r = try OpenAICompatibleProvider(config: config(.openai), session: .shared).makeRequest(system: "S", user: "U", maxTokens: 900)
        XCTAssertEqual(r.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let b = try body(r)
        XCTAssertEqual(b["model"] as? String, "m-1")
        XCTAssertEqual(b["max_completion_tokens"] as? Int, 900)
        XCTAssertNil(b["max_tokens"])
        let messages = try XCTUnwrap(b["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "system", "content": "S"], ["role": "user", "content": "U"]])
    }

    func test_openRouterAndZAIRequests() throws {
        let or = try OpenAICompatibleProvider(config: config(.openrouter), session: .shared).makeRequest(system: "S", user: "U", maxTokens: 10)
        XCTAssertEqual(or.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(or.value(forHTTPHeaderField: "X-Title"), "Dyktando")
        XCTAssertEqual(try body(or)["max_tokens"] as? Int, 10)

        let zai = try OpenAICompatibleProvider(config: config(.zai), session: .shared).makeRequest(system: "S", user: "U", maxTokens: 10)
        XCTAssertEqual(zai.url?.absoluteString, "https://api.z.ai/api/paas/v4/chat/completions")
        XCTAssertEqual(try body(zai)["max_tokens"] as? Int, 10)
    }

    func test_customBaseURL_trailingSlashIgnored() throws {
        var c = config(.openai)
        c.baseURL = "http://localhost:1234/v1/"
        let r = try OpenAICompatibleProvider(config: c, session: .shared).makeRequest(system: "", user: "", maxTokens: 1)
        XCTAssertEqual(r.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
    }

    func test_anthropicRequest() throws {
        let r = try AnthropicProvider(config: config(.anthropic, model: "claude-opus-5-5"), session: .shared)
            .makeRequest(system: "S", user: "U", maxTokens: 16_000)
        XCTAssertEqual(r.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(r.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(r.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"))
        let b = try body(r)
        XCTAssertEqual(b["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(b["system"] as? String, "S")
        XCTAssertEqual(b["max_tokens"] as? Int, 16_000)
        XCTAssertEqual(b["fallbacks"] as? String, "default")
        XCTAssertEqual((b["output_config"] as? [String: String])?["effort"], "medium")
        XCTAssertNil(b["thinking"], "Opus 5.5: thinking zostaje domyślne (adaptive)")
    }

    func test_anthropicDefaultModel() {
        XCTAssertEqual(AIProviderID.anthropic.defaultModel, "claude-opus-5-5")
    }

    // MARK: Odpowiedzi

    func test_parseAnthropic_joinsTextBlocks_skipsThinking() throws {
        let json: [String: Any] = ["stop_reason": "end_turn", "content": [
            ["type": "thinking", "thinking": ""], ["type": "text", "text": "## Streszczenie\n"], ["type": "text", "text": "Ok."]]]
        XCTAssertEqual(try AnthropicProvider.parseMessage(json), "## Streszczenie\nOk.")
    }

    func test_parseAnthropic_refusal_isError() {
        let json: [String: Any] = ["stop_reason": "refusal", "content": [], "stop_details": ["category": "cyber"]]
        XCTAssertThrowsError(try AnthropicProvider.parseMessage(json)) { error in
            XCTAssertTrue((error as? LLMError)?.message.contains("odmówił") == true)
        }
    }

    func test_parseOpenAI() throws {
        let json: [String: Any] = ["choices": [["message": ["content": " Podsumowanie "], "finish_reason": "stop"]]]
        XCTAssertEqual(try OpenAICompatibleProvider.parseCompletion(json), "Podsumowanie")
        XCTAssertThrowsError(try OpenAICompatibleProvider.parseCompletion(["choices": [["message": ["content": ""], "finish_reason": "length"]]]))
    }

    func test_http401_givesReadableError_noRetry() async {
        StubURLProtocol.responses = [(401, #"{"error":{"message":"invalid x-api-key"}}"#, [:])]
        let provider = AnthropicProvider(config: config(.anthropic), session: StubURLProtocol.session)
        do {
            _ = try await provider.complete(system: "s", user: "u", maxTokens: 5)
            XCTFail("powinien rzucić")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Klucz API odrzucony"), error.localizedDescription)
            XCTAssertEqual(StubURLProtocol.requests.count, 1)
        }
    }

    func test_http429_isRetried() async throws {
        StubURLProtocol.responses = [
            (429, #"{"error":{"message":"slow down"}}"#, ["retry-after": "0"]),
            (200, #"{"choices":[{"message":{"content":"Gotowe"},"finish_reason":"stop"}]}"#, [:]),
        ]
        let provider = OpenAICompatibleProvider(config: config(.openrouter), session: StubURLProtocol.session)
        let text = try await provider.complete(system: "s", user: "u", maxTokens: 5)
        XCTAssertEqual(text, "Gotowe")
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func test_listModels() async throws {
        StubURLProtocol.responses = [(200, #"{"data":[{"id":"glm-b"},{"id":"glm-a"}]}"#, [:])]
        let models = try await OpenAICompatibleProvider(config: config(.zai), session: StubURLProtocol.session).listModels()
        XCTAssertEqual(models, ["glm-a", "glm-b"])
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.absoluteString, "https://api.z.ai/api/paas/v4/models")
    }

    // MARK: Podsumowanie

    private final class FakeProvider: LLMProvider, @unchecked Sendable {
        var calls: [String] = []
        func complete(system: String, user: String, maxTokens: Int) async throws -> String {
            calls.append(user)
            return "notatka \(calls.count)"
        }
        func listModels() async throws -> [String] { [] }
    }

    func test_chunks_splitOnlyBetweenLines() {
        let lines = (1...100).map { "[00:00:\($0)] **Ja:** zdanie numer \($0)" }
        let transcript = lines.joined(separator: "\n")
        let parts = MeetingSummarizer.chunks(of: transcript, limit: 500)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 500 })
        XCTAssertEqual(parts.joined(separator: "\n"), transcript, "nic nie ginie ani się nie dubluje")
    }

    func test_shortTranscript_singleCall() async throws {
        let fake = FakeProvider()
        let s = MeetingSummarizer(provider: fake, config: config(.anthropic))
        let out = try await s.summarize(transcript: "krótko", prompt: "P") { _, _ in }
        XCTAssertEqual(out, "notatka 1")
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertTrue(fake.calls[0].contains("krótko"))
    }

    func test_longTranscript_mapReduce() async throws {
        let fake = FakeProvider()
        let s = MeetingSummarizer(provider: fake, config: config(.openai))  // limit 180k znaków
        let transcript = (0..<4_000).map { "[00:00:00] **Rozmówca 1:** " + String(repeating: "słowo ", count: 10) + "\($0)" }
            .joined(separator: "\n")
        _ = try await s.summarize(transcript: transcript, prompt: "P") { _, _ in }
        let parts = MeetingSummarizer.chunks(of: transcript, limit: AIProviderID.openai.chunkCharacters).count
        XCTAssertGreaterThan(parts, 1)
        XCTAssertEqual(fake.calls.count, parts + 1, "części + złożenie")
        XCTAssertTrue(fake.calls.last!.contains("### Część 1"))
    }

    // MARK: Pęk kluczy

    func test_keychain_roundTrip() throws {
        let kc = KeychainStore(service: "com.bartekzimny.dyktando.tests.\(UUID().uuidString)")
        defer { kc.delete("p") }
        XCTAssertNil(kc.get("p"))
        try kc.set("sekret-1", for: "p")
        XCTAssertEqual(kc.get("p"), "sekret-1")
        try kc.set("sekret-2", for: "p")
        XCTAssertEqual(kc.get("p"), "sekret-2")
        kc.delete("p")
        XCTAssertFalse(kc.has("p"))
    }

    // MARK: Retencja

    func test_retention_deletesOnlyOldTranscribedAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ret-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let now = Date()
        func make(daysAgo: Double, transcribed: Bool) throws -> String {
            var m = try store.create(startedAt: now.addingTimeInterval(-daysAgo * 86_400), hasSystemAudio: false)
            m.state = transcribed ? .transcribed : .recorded
            m.endedAt = m.startedAt.addingTimeInterval(60)
            try store.save(m)
            try Data([1]).write(to: store.audioFolder(for: m.id).appendingPathComponent("mic-000.caf"))
            if transcribed { try "x".write(to: store.transcriptURL(for: m.id), atomically: true, encoding: .utf8) }
            return m.id
        }
        let oldDone = try make(daysAgo: 40, transcribed: true)
        let oldNotTranscribed = try make(daysAgo: 40, transcribed: false)
        let recent = try make(daysAgo: 5, transcribed: true)

        XCTAssertEqual(store.applyRetention(days: 30, now: now), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.audioFolder(for: oldDone).path))
        XCTAssertEqual(store.load(oldDone)?.audioDeleted, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.transcriptURL(for: oldDone).path), "tekst zostaje")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioFolder(for: oldNotTranscribed).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioFolder(for: recent).path))
        XCTAssertEqual(store.applyRetention(days: 0, now: now), 0, "0 = trzymaj zawsze")
    }

    // MARK: Wykrywanie spotkań

    func test_detector_asksOncePerMicSession() {
        var logic = MeetingDetectionLogic()
        XCTAssertNil(logic.update(activeBundleIDs: ["com.apple.Music"], isRecording: false, enabled: true))
        XCTAssertEqual(logic.update(activeBundleIDs: ["us.zoom.xos"], isRecording: false, enabled: true), "us.zoom.xos")
        XCTAssertNil(logic.update(activeBundleIDs: ["us.zoom.xos"], isRecording: false, enabled: true), "nie pytaj drugi raz")
        XCTAssertNil(logic.update(activeBundleIDs: [], isRecording: false, enabled: true))
        XCTAssertEqual(logic.update(activeBundleIDs: ["us.zoom.xos"], isRecording: false, enabled: true), "us.zoom.xos",
                       "nowa rozmowa po przerwie — pytaj znowu")
    }

    func test_detector_browserHelpers_matchByPrefix() {
        XCTAssertEqual(MeetingDetectionLogic.matchingApp("com.google.Chrome.helper"), "com.google.Chrome")
        XCTAssertNil(MeetingDetectionLogic.matchingApp("com.google.Chromeish"))
    }

    func test_detector_silentWhileRecordingOrDisabled() {
        var logic = MeetingDetectionLogic()
        XCTAssertNil(logic.update(activeBundleIDs: ["com.microsoft.teams2"], isRecording: true, enabled: true))
        XCTAssertNil(logic.update(activeBundleIDs: ["com.microsoft.teams2"], isRecording: false, enabled: true),
                     "rozmowa, która trwała w trakcie nagrywania, nie wywołuje podpowiedzi po stopie")
        var off = MeetingDetectionLogic()
        XCTAssertNil(off.update(activeBundleIDs: ["us.zoom.xos"], isRecording: false, enabled: false))
    }

    // MARK: Anthropic — parametry zależne od modelu (recenzja PR #2)

    func test_anthropic_haiku_noEffortNoFallbacks() throws {
        let r = try AnthropicProvider(config: config(.anthropic, model: "claude-haiku-4-5-20251001"), session: .shared)
            .makeRequest(system: "S", user: "U", maxTokens: 100)
        let b = try body(r)
        XCTAssertNil(b["output_config"], "Haiku 4.5 zwraca 400 na effort")
        XCTAssertNil(b["fallbacks"])
        XCTAssertNil(r.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func test_anthropic_sonnet46_effortButNoFallbacks() throws {
        let r = try AnthropicProvider(config: config(.anthropic, model: "claude-sonnet-4-6"), session: .shared)
            .makeRequest(system: "S", user: "U", maxTokens: 100)
        let b = try body(r)
        XCTAssertNotNil(b["output_config"])
        XCTAssertNil(b["fallbacks"])
    }

    func test_anthropic_customHost_noFallbacks() throws {
        var c = config(.anthropic, model: "claude-opus-5-5")
        c.baseURL = "https://gateway.example.com/v1"
        let r = try AnthropicProvider(config: c, session: .shared).makeRequest(system: "S", user: "U", maxTokens: 100)
        XCTAssertNil(try body(r)["fallbacks"])
        XCTAssertNil(r.value(forHTTPHeaderField: "anthropic-beta"))
        XCTAssertEqual(r.url?.host, "gateway.example.com")
    }
}
