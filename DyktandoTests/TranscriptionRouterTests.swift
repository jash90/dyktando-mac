import XCTest
@testable import Dyktando

final class TranscriptionRouterTests: XCTestCase {
    func test_routeAll_collectsResultsFromAllInstalledEngines() async {
        let a = FakeEngine(id: .appleSpeechPL, delay: 30, text: "alpha")
        let b = FakeEngine(id: .parakeetTDTv3, delay: 30, text: "beta")
        let router = TranscriptionRouter(engines: [a, b])
        let rows = await router.routeAll(samples: [],
                                         sampleRate: 16_000,
                                         mode: .single(Locale(identifier: "pl-PL")))
        XCTAssertEqual(Set(rows.map(\.engineID)), [.appleSpeechPL, .parakeetTDTv3])
        XCTAssertEqual(Set(rows.map(\.result.text)), ["alpha", "beta"])
    }

    func test_routeAll_ignoresFailingEngines() async {
        let good = FakeEngine(id: .appleSpeechPL, delay: 10, text: "ok")
        let bad = FakeEngine(id: .parakeetTDTv3, delay: 10, text: "", throws: true)
        let router = TranscriptionRouter(engines: [good, bad])
        let rows = await router.routeAll(samples: [],
                                         sampleRate: 16_000,
                                         mode: .single(Locale(identifier: "pl-PL")))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.engineID, .appleSpeechPL)
    }
}

private final class FakeEngine: TranscriptionEngine, @unchecked Sendable {
    let id: EngineID
    let displayName = "fake"
    let supportedLanguages: Set<Locale> = []
    var isInstalled = true
    private let delayMs: UInt64
    private let text: String
    private let shouldThrow: Bool

    init(id: EngineID, delay: UInt64, text: String, throws shouldThrow: Bool = false) {
        self.id = id
        self.delayMs = delay
        self.text = text
        self.shouldThrow = shouldThrow
    }

    func install(progress: @escaping @Sendable (Double) -> Void) async throws { progress(1) }
    func uninstall() throws {}
    func transcribe(samples: [Float], sampleRate: Double, mode: LanguageMode) async throws -> TranscriptionResult {
        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
        if shouldThrow { throw EngineError.notInstalled }
        return TranscriptionResult(
            text: text,
            language: Locale(identifier: "pl-PL"),
            inferenceMillis: Int(delayMs),
            confidence: nil)
    }
}
