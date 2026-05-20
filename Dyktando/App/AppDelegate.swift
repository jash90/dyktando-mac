import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyMonitor?
    private let audio = AudioCapture()
    let hud = HUDController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        audio.delegate = self
        hotkeys = HotkeyMonitor { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .startCapture:
            hud.show(near: NSEvent.mouseLocation)
            hud.state.beginListening()
            do { try audio.start() }
            catch { print("audio.start failed: \(error)") }
        case .stopCapture:
            audio.stop()
            hud.state.beginTranscribing()
        case .switchModel, .openSettings:
            break
        }
    }
}

extension AppDelegate: AudioCaptureDelegate {
    nonisolated func audioCapture(_ capture: AudioCapture, level rms: Float) {
        Task { @MainActor [weak self] in
            self?.hud.state.level = rms
        }
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
        Task { @MainActor [weak self] in
            self?.hud.state.finish(preview: "(audio captured)")
            // HUD self-hides via finish(...) → .idle after 800ms; no explicit hide needed.
        }
    }
}
