import SwiftUI

enum HUDPhase: Equatable {
    case idle
    case listening
    case transcribing
    case preview(String)
}

@MainActor
final class HUDState: ObservableObject {
    @Published private(set) var phase: HUDPhase = .idle
    @Published var level: Float = 0

    private var autoIdleTask: Task<Void, Never>?

    func beginListening() {
        autoIdleTask?.cancel()
        phase = .listening
    }

    func beginTranscribing() {
        autoIdleTask?.cancel()
        phase = .transcribing
    }

    func finish(preview: String) {
        autoIdleTask?.cancel()
        phase = .preview(preview)
        autoIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled, let self else { return }
            self.phase = .idle
            self.level = 0
        }
    }

    func resetToIdle() {
        autoIdleTask?.cancel()
        phase = .idle
    }
}
