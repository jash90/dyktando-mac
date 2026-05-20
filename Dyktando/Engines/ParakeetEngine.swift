import Foundation
import FluidAudio

// Disambiguate from FluidAudio's ASRResult.
private typealias EngineResult = Dyktando.TranscriptionResult

final class ParakeetEngine: TranscriptionEngine, @unchecked Sendable {
    let id: EngineID = .parakeetTDTv3
    let displayName = "Parakeet TDT v3"

    // The v3 model supports a broad set of European languages via script-aware
    // token filtering (Language enum in FluidAudio).
    let supportedLanguages: Set<Locale> = Set([
        "pl", "en", "de", "fr", "es", "it", "nl", "pt", "cs", "sk",
        "hu", "ro", "bg", "hr", "da", "fi", "el", "et", "lv", "lt",
        "ru", "uk", "sl", "sv"
    ].map(Locale.init(identifier:)))

    // FluidAudio stores models at:
    //   ~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3/
    // (via MLModelConfigurationUtils.defaultModelsDirectory(for: .parakeetV3))
    private let modelCacheDir: URL = AsrModels.defaultCacheDirectory(for: .v3)

    private var manager: AsrManager?

    var isInstalled: Bool {
        AsrModels.modelsExist(at: modelCacheDir, version: .v3)
    }

    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        let models = try await AsrModels.downloadAndLoad(
            to: modelCacheDir,
            version: .v3,
            progressHandler: { p in progress(p.fractionCompleted) }
        )
        manager = AsrManager(models: models)
        progress(1.0)
    }

    func uninstall() throws {
        manager = nil
        let fm = FileManager.default
        // Remove FluidAudio's cache directory for the v3 model.
        if fm.fileExists(atPath: modelCacheDir.path) {
            try fm.removeItem(at: modelCacheDir)
        }
    }

    func transcribe(samples: [Float],
                    sampleRate: Double,
                    mode: LanguageMode) async throws -> Dyktando.TranscriptionResult {
        // Lazy-load: if not yet initialized but models exist on disk, load them.
        if manager == nil {
            if isInstalled {
                let models = try await AsrModels.load(from: modelCacheDir, version: .v3)
                manager = AsrManager(models: models)
            } else {
                throw EngineError.notInstalled
            }
        }
        guard let manager else { throw EngineError.notInstalled }

        let start = Date()

        // Create a fresh TdtDecoderState for each single-shot transcription.
        var decoderState = TdtDecoderState.make(decoderLayers: 2)

        // Map our LanguageMode to FluidAudio's Language hint (v3 uses this for
        // script-aware token filtering; v2 ignores it silently).
        let languageHint = Self.languageHint(for: mode)

        let asrResult = try await manager.transcribe(
            samples,
            decoderState: &decoderState,
            language: languageHint
        )

        let detectedLanguage = languageHint.map { lang in
            Locale(identifier: lang.rawValue)
        } ?? Locale(identifier: "pl")

        return EngineResult(
            text: asrResult.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: detectedLanguage,
            inferenceMillis: Int(Date().timeIntervalSince(start) * 1000),
            confidence: Double(asrResult.confidence)
        )
    }

    // MARK: - Private helpers

    private static func languageHint(for mode: LanguageMode) -> Language? {
        let identifier: String?
        switch mode {
        case .single(let locale):
            identifier = String(locale.identifier.prefix(2))
        case .multilingualAuto(let locales):
            // Prefer Polish if present; else use first locale.
            identifier = locales.first { $0.identifier.hasPrefix("pl") }?.identifier
                ?? locales.first.map { String($0.identifier.prefix(2)) }
        case .mixed(let primary, _):
            identifier = String(primary.identifier.prefix(2))
        }
        guard let id = identifier else { return nil }
        return Language(rawValue: id)
    }
}
