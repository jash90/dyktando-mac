import AppKit
import AVFAudio
import SwiftUI

@MainActor
final class PermissionsService: ObservableObject {
    @Published private(set) var microphone: AVAudioApplication.recordPermission
    @Published private(set) var accessibility: Bool

    init() {
        microphone = AVAudioApplication.shared.recordPermission
        accessibility = AXIsProcessTrusted()
    }

    /// Requests microphone access. Returns the granted state after the system prompt.
    func requestMicrophone() async -> Bool {
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        microphone = AVAudioApplication.shared.recordPermission
        return granted
    }

    /// Opens System Settings to Privacy & Security → Accessibility, then polls
    /// AXIsProcessTrusted() until the user grants permission.
    func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        Task { await pollAccessibilityUntilTrusted() }
    }

    /// Refresh accessibility status synchronously (callers can use this in Settings UI).
    func refreshAccessibility() {
        accessibility = AXIsProcessTrusted()
    }

    private func pollAccessibilityUntilTrusted() async {
        // Bounded poll for up to 5 minutes to avoid runaway tasks.
        for _ in 0..<600 {
            if AXIsProcessTrusted() {
                accessibility = true
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
