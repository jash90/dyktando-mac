import Foundation

@MainActor
final class EngineRegistry: ObservableObject {
    static let shared = EngineRegistry()

    @Published private(set) var engines: [EngineID: TranscriptionEngine] = [:]

    init() {
        engines[.parakeetTDTv3] = ParakeetEngine()
    }

    /// Returns the user's transcription engine. With only Parakeet wired up,
    /// the `prefs` argument is kept for source-compatibility with the rest
    /// of the app but doesn't change the outcome.
    func active(prefs: Preferences) -> TranscriptionEngine {
        return engines[.parakeetTDTv3]!
    }

    func engine(for id: EngineID) -> TranscriptionEngine? {
        engines[id]
    }
}
