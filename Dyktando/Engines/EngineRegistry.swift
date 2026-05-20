import Foundation

@MainActor
final class EngineRegistry: ObservableObject {
    static let shared = EngineRegistry()

    @Published private(set) var engines: [EngineID: TranscriptionEngine] = [:]

    init() {
        engines[.appleSpeechPL] = AppleSpeechEngine()
        engines[.whisperLargeV3Turbo] = WhisperKitEngine(variant: .largeV3Turbo)
        engines[.whisperLargeV3] = WhisperKitEngine(variant: .largeV3)
        engines[.parakeetTDTv3] = ParakeetEngine()
    }

    /// Returns the engine the user has chosen as default, falling back to
    /// Apple Speech (always installed) if the chosen one isn't available.
    func active(prefs: Preferences) -> TranscriptionEngine {
        if let id = EngineID(rawValue: prefs.defaultEngineID),
           let engine = engines[id],
           engine.isInstalled {
            return engine
        }
        // Apple Speech is the system-provided fallback; always present.
        return engines[.appleSpeechPL]!
    }

    func engine(for id: EngineID) -> TranscriptionEngine? {
        engines[id]
    }
}
