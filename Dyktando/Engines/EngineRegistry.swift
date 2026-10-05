import Foundation

@MainActor
final class EngineRegistry: ObservableObject {
    static let shared = EngineRegistry()

    @Published private(set) var engines: [EngineID: TranscriptionEngine] = [:]

    init() {
        engines[.parakeetTDTv3] = ParakeetEngine()
        for variant in [MLXSidecarEngine.canary, MLXSidecarEngine.whisperTurbo, MLXSidecarEngine.whisperLarge] {
            engines[variant.id] = MLXSidecarEngine(variant)
        }
    }

    /// Silnik wybrany w Ustawieniach → Modele. Gdy wybrany nie jest zainstalowany
    /// (albo zapisany identyfikator jest nieznany), wracamy do Parakeeta.
    func active(prefs: Preferences) -> TranscriptionEngine {
        engines[Self.resolve(preferred: prefs.defaultEngineID, isInstalled: { [engines] in
            engines[$0]?.isInstalled ?? false
        })]!
    }

    nonisolated static func resolve(preferred raw: String, isInstalled: (EngineID) -> Bool) -> EngineID {
        if let id = EngineID(rawValue: raw), id != .parakeetTDTv3, isInstalled(id) {
            return id
        }
        return .parakeetTDTv3
    }

    /// Osobna instancja silnika (np. do długiej transkrypcji spotkania), żeby nie dzielić stanu
    /// z instancją używaną przez dyktowanie F5. Modele na dysku są wspólne.
    nonisolated static func makeEngine(_ id: EngineID) -> TranscriptionEngine {
        switch id {
        case .parakeetTDTv3:       return ParakeetEngine()
        case .canary1bV2:          return MLXSidecarEngine(MLXSidecarEngine.canary)
        case .whisperLargeV3Turbo: return MLXSidecarEngine(MLXSidecarEngine.whisperTurbo)
        case .whisperLargeV3:      return MLXSidecarEngine(MLXSidecarEngine.whisperLarge)
        }
    }

    func engine(for id: EngineID) -> TranscriptionEngine? {
        engines[id]
    }
}
