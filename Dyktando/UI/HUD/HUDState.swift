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

    func beginListening() { phase = .listening }
    func beginTranscribing() { phase = .transcribing }

    func finish(preview: String) {
        phase = .preview(preview)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if case .preview = phase { phase = .idle }
        }
    }

    func resetToIdle() { phase = .idle }
}
