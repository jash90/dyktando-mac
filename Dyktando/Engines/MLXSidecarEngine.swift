import Foundation

// Disambiguate from library result types (konwencja z ParakeetEngine).
private typealias EngineResult = Dyktando.TranscriptionResult

/// Silnik działający przez lokalny serwer MLX (`MLXSidecar`): Canary-1b-v2 i Whisper large-v3(-turbo).
final class MLXSidecarEngine: TranscriptionEngine, @unchecked Sendable {
    struct Variant: Sendable {
        let id: EngineID
        let displayName: String
        let modelKey: String      // klucz w stt_server.py
        let hfRepo: String        // do odinstalowania (cache Hugging Face)
        let autoDetectsLanguage: Bool
    }

    static let canary = Variant(id: .canary1bV2, displayName: "Canary-1b-v2",
                                modelKey: "canary", hfRepo: "qfuxa/canary-mlx",
                                autoDetectsLanguage: false)
    static let whisperTurbo = Variant(id: .whisperLargeV3Turbo, displayName: "Whisper large-v3-turbo",
                                      modelKey: "whisper-turbo", hfRepo: "mlx-community/whisper-large-v3-turbo",
                                      autoDetectsLanguage: true)
    static let whisperLarge = Variant(id: .whisperLargeV3, displayName: "Whisper large-v3",
                                      modelKey: "whisper-large", hfRepo: "mlx-community/whisper-large-v3-mlx",
                                      autoDetectsLanguage: true)

    let variant: Variant
    var id: EngineID { variant.id }
    var displayName: String { variant.displayName }
    let detail = "MLX · lokalny serwer Python (wymaga uv)"

    var supportedLanguages: Set<Locale> {
        // Canary: 25 języków europejskich; Whisper: ~100 — w aplikacji liczą się te z ustawień języka.
        Set(["pl", "en", "de", "fr", "es", "it", "nl", "pt", "cs", "sk", "uk", "ru"].map(Locale.init(identifier:)))
    }

    init(_ variant: Variant) { self.variant = variant }

    private var markerURL: URL {
        MLXSidecar.root.appendingPathComponent("installed-\(variant.modelKey)")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
            && FileManager.default.isExecutableFile(atPath: MLXSidecar.venvPython.path)
    }

    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.05)
        // Przez ensureServer (wspólny start), nie ensureEnvironment — inaczej instalacja w trakcie
        // prewarmu odpaliłaby drugi `uv sync` na tym samym venv.
        try await MLXSidecar.shared.ensureServer()   // pierwsza instalacja: 1–3 min
        progress(0.4)
        try await MLXSidecar.shared.prepare(model: variant.modelKey)   // pobranie modelu: do kilku min
        try Data().write(to: markerURL)
        progress(1.0)
    }

    func uninstall() throws {
        try? FileManager.default.removeItem(at: markerURL)
        // Usuwamy pobrane wagi z cache Hugging Face, żeby zwolnić miejsce.
        let cache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent("models--" + variant.hfRepo.replacingOccurrences(of: "/", with: "--"))
        if FileManager.default.fileExists(atPath: cache.path) {
            try FileManager.default.removeItem(at: cache)
        }
    }

    func transcribe(samples: [Float],
                    sampleRate: Double,
                    mode: LanguageMode) async throws -> Dyktando.TranscriptionResult {
        guard isInstalled else { throw EngineError.notInstalled }
        let start = Date()
        let pcm = sampleRate == 16_000 ? samples : Self.resample(samples, from: sampleRate, to: 16_000)
        let language = Self.languageCode(for: mode, autoDetects: variant.autoDetectsLanguage)
        let result = try await MLXSidecar.shared.transcribe(model: variant.modelKey, samples: pcm, language: language)
        return EngineResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: Locale(identifier: result.language ?? language ?? "pl"),
            inferenceMillis: Int(Date().timeIntervalSince(start) * 1000),
            confidence: nil
        )
    }

    // MARK: - Pomocnicze

    /// Kod języka dla serwera. `nil` = niech model wykryje sam (tylko Whisper).
    static func languageCode(for mode: LanguageMode, autoDetects: Bool) -> String? {
        switch mode {
        case .single(let locale):
            return String(locale.identifier.prefix(2))
        case .mixed(let primary, _):
            return String(primary.identifier.prefix(2))
        case .multilingualAuto(let allowed):
            if autoDetects { return nil }
            let codes = allowed.map { String($0.identifier.prefix(2)) }
            return codes.contains("pl") ? "pl" : codes.sorted().first ?? "pl"
        }
    }

    /// Liniowe przepróbkowanie (AudioCapture i tak daje 16 kHz — to tylko zabezpieczenie).
    static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        guard !x.isEmpty, from > 0, from != to else { return x }
        let n = Int((Double(x.count) * to / from).rounded())
        let step = from / to
        return (0..<n).map { i in
            let pos = Double(i) * step
            let j = min(Int(pos), x.count - 1)
            let k = min(j + 1, x.count - 1)
            let t = Float(pos - Double(j))
            return x[j] * (1 - t) + x[k] * t
        }
    }
}
