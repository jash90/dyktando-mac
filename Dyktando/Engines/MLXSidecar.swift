import Foundation

/// Lokalny serwer MLX (Python) dla modeli, których nie ma w Swifcie: Canary-1b-v2,
/// Whisper large-v3-turbo, Whisper large-v3. Kod serwera jest w zasobach aplikacji
/// (`stt_server.py`, `pyproject.toml`, `uv.lock`); przy instalacji pierwszego modelu
/// kopiujemy go do `AppPaths.support/sidecar/` i tworzymy tam venv przez `uv sync`.
/// Serwer startuje na żądanie i słucha tylko na 127.0.0.1.
actor MLXSidecar {
    static let shared = MLXSidecar()

    static let port = 7863
    static let resourceFiles = [("stt_server", "py"), ("pyproject", "toml"), ("uv", "lock")]

    enum SidecarError: LocalizedError {
        case uvMissing
        case resourcesMissing
        case setupFailed(String)
        case serverDidNotStart(String)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .uvMissing:
                return "Brak narzędzia uv (potrzebne do modeli MLX). Zainstaluj: brew install uv"
            case .resourcesMissing:
                return "Brak plików serwera MLX w paczce aplikacji."
            case .setupFailed(let log):
                return "Instalacja środowiska MLX nie powiodła się:\n\(log)"
            case .serverDidNotStart(let log):
                return "Serwer MLX nie wystartował:\n\(log)"
            case .server(let message):
                return "Serwer MLX: \(message)"
            }
        }
    }

    private var process: Process?
    /// Wspólny start serwera — actor jest reentrant, więc bez tego dwa równoległe wywołania
    /// (np. prewarm + dyktowanie) uruchomiłyby dwa procesy Pythona.
    private var startTask: Task<Void, Error>?
    /// Losowany przy każdym uruchomieniu aplikacji; serwer odrzuca żądania bez niego
    /// (chroni przed stronami WWW wysyłającymi POST na 127.0.0.1).
    private let token = UUID().uuidString + UUID().uuidString

    // MARK: - Ścieżki

    nonisolated static var root: URL { AppPaths.support.appendingPathComponent("sidecar", isDirectory: true) }
    nonisolated static var sourceDir: URL { root.appendingPathComponent("src", isDirectory: true) }
    nonisolated static var venvPython: URL { root.appendingPathComponent("venv/bin/python") }
    nonisolated static var logURL: URL { root.appendingPathComponent("server.log") }

    /// uv.lock, z którym ostatnio udał się `uv sync` (zapisywany po synchronizacji).
    nonisolated static var syncedLockURL: URL { root.appendingPathComponent("synced-uv.lock") }

    nonisolated static var isEnvironmentReady: Bool {
        FileManager.default.isExecutableFile(atPath: venvPython.path)
            && FileManager.default.contentsEqual(atPath: bundledLock?.path ?? "", andPath: syncedLockURL.path)
    }

    nonisolated private static var bundledLock: URL? {
        Bundle.main.url(forResource: "uv", withExtension: "lock")
    }

    nonisolated static func findUV() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/opt/homebrew/bin/uv", "\(home)/.local/bin/uv", "\(home)/.cargo/bin/uv", "/usr/local/bin/uv"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    // MARK: - Środowisko

    /// Kopiuje kod serwera z paczki aplikacji i tworzy venv (`uv sync`). Pomija, gdy aktualne.
    func ensureEnvironment() async throws {
        // Kod serwera kopiujemy przy każdej zmianie (aktualizacja aplikacji), a `uv sync`
        // uruchamiamy tylko wtedy, gdy zmieniły się zależności (uv.lock).
        if try syncSourceFiles() { terminateProcess() }  // działający serwer ma stary kod
        if Self.isEnvironmentReady { return }
        guard let uv = Self.findUV() else { throw SidecarError.uvMissing }
        terminateProcess()

        let (status, output) = try await Self.run(uv, logURL: Self.root.appendingPathComponent("uv-sync.log"), arguments: [
            "sync", "--frozen", "--python", "3.11", "--project", Self.sourceDir.path,
        ], environment: ["UV_PROJECT_ENVIRONMENT": Self.root.appendingPathComponent("venv").path])
        guard status == 0 else { throw SidecarError.setupFailed(String(output.suffix(1500))) }
        try? FileManager.default.removeItem(at: Self.syncedLockURL)
        try FileManager.default.copyItem(at: Self.sourceDir.appendingPathComponent("uv.lock"), to: Self.syncedLockURL)
    }

    /// Kopiuje pliki serwera z paczki aplikacji, jeśli się różnią. Zwraca `true`, gdy coś zmieniono.
    private func syncSourceFiles() throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.sourceDir, withIntermediateDirectories: true)
        var changed = false
        for (name, ext) in Self.resourceFiles {
            guard let src = Bundle.main.url(forResource: name, withExtension: ext) else {
                throw SidecarError.resourcesMissing
            }
            let dst = Self.sourceDir.appendingPathComponent("\(name).\(ext)")
            if fm.contentsEqual(atPath: src.path, andPath: dst.path) { continue }
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
            changed = true
        }
        return changed
    }

    // MARK: - Serwer

    func ensureServer() async throws {
        if let existing = startTask {
            try await existing.value
            if await health() { return }
            startTask = nil  // serwer padł po starcie — uruchom ponownie
        }
        let task = Task { try await self.startServer() }
        startTask = task
        do {
            try await task.value
        } catch {
            startTask = nil  // następna próba może spróbować od nowa
            throw error
        }
    }

    private func startServer() async throws {
        try await ensureEnvironment()
        if await health() { return }
        let script = Self.sourceDir.appendingPathComponent("stt_server.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw SidecarError.resourcesMissing
        }
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: Self.logURL)
        let p = Process()
        p.executableURL = Self.venvPython
        // --parent-pid: serwer kończy się sam, gdy aplikacja zniknie (np. pkill, crash) — bez sierot w pamięci.
        p.arguments = [script.path, "--port", String(Self.port), "--parent-pid", String(getpid())]
        p.standardOutput = log
        p.standardError = log
        p.environment = ProcessInfo.processInfo.environment.merging(["DYKTANDO_SIDECAR_TOKEN": token]) { $1 }
        try p.run()
        process = p
        NSLog("[MLXSidecar] started pid=%d", p.processIdentifier)

        for _ in 0..<80 {  // do 20 s
            try await Task.sleep(nanoseconds: 250_000_000)
            if await health() { return }
            if !p.isRunning { break }
        }
        let tail = (try? String(contentsOf: Self.logURL, encoding: .utf8)).map { String($0.suffix(1500)) } ?? ""
        throw SidecarError.serverDidNotStart(tail)
    }

    /// Zatrzymanie z zewnątrz (zamknięcie aplikacji): proces + zapomnienie startu.
    func stop() {
        terminateProcess()
        startTask = nil
    }

    /// Tylko zabija proces. Używane w trakcie startu (ensureEnvironment) — nie może czyścić
    /// `startTask`, bo to ten sam, wciąż trwający start; inaczej równoległe wywołania
    /// odpaliłyby drugi serwer w czasie `uv sync`.
    private func terminateProcess() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    /// Nasz serwer = 200 + nasz token + znacznik usługi (obcy proces na porcie 7863 nie przejdzie).
    func health() async -> Bool {
        var req = URLRequest(url: Self.url("/health"))
        req.timeoutInterval = 1
        req.setValue(token, forHTTPHeaderField: "X-Dyktando-Token")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["service"] as? String == "dyktando-sidecar"
    }

    /// Pobiera (pierwszy raz) i ładuje model do pamięci serwera.
    func prepare(model: String) async throws {
        try await ensureServer()
        _ = try await post("/prepare", body: ["model": model], timeout: 3600)
    }

    func transcribe(model: String, samples: [Float], language: String?) async throws -> (text: String, language: String?) {
        try await ensureServer()
        var body: [String: Any] = ["model": model, "samples_b64": Self.encodeSamples(samples)]
        body["language"] = language ?? NSNull()
        let json = try await post("/transcribe", body: body, timeout: 600)
        return ((json["text"] as? String) ?? "", json["language"] as? String)
    }

    // MARK: - Pomocnicze

    /// Float32 little-endian → base64 (format oczekiwany przez `stt_server.py`).
    nonisolated static func encodeSamples(_ samples: [Float]) -> String {
        let le = samples.map { $0.bitPattern.littleEndian }
        return le.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
    }

    nonisolated private static func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    private func post(_ path: String, body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        var req = URLRequest(url: Self.url(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-Dyktando-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw SidecarError.server((json["error"] as? String) ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return json
    }

    /// Uruchamia proces z wyjściem do pliku (nie do Pipe: Pipe czytany dopiero po zakończeniu
    /// blokuje proces, gdy wypisze więcej niż bufor ~64 KB). Zwraca kod wyjścia i koniec logu.
    private static func run(_ exe: URL, logURL: URL, arguments: [String],
                            environment: [String: String]) async throws -> (Int32, String) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        let p = Process()
        p.executableURL = exe
        p.arguments = arguments
        p.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        p.standardOutput = log
        p.standardError = log
        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
        try? log.close()
        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        return (status, String(output.suffix(4000)))
    }
}
