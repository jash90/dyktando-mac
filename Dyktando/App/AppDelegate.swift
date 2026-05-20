import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyMonitor?
    private let audio = AudioCapture()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        audio.delegate = self

        hotkeys = HotkeyMonitor { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .startCapture(_):
            try? audio.start()
        case .stopCapture:
            audio.stop()
        case .switchModel, .openSettings:
            break  // wired in later milestones
        }
    }
}

extension AppDelegate: AudioCaptureDelegate {
    nonisolated func audioCapture(_ capture: AudioCapture, level rms: Float) {
        // M1.4 will surface this to the HUD.
    }

    nonisolated func audioCapture(_ capture: AudioCapture,
                                  finishedWith samples: [Float],
                                  sampleRate: Double) {
        DispatchQueue.global(qos: .utility).async {
            let url = AppPaths.support.appendingPathComponent("last-recording.caf")
            do {
                try WAVWriter.write(samples, sampleRate: sampleRate, to: url)
                print("Saved recording: \(url.path)")
            } catch {
                print("WAV write failed: \(error)")
            }
        }
    }
}
