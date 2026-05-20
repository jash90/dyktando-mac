import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyMonitor?
    private let audio = AudioCapture()
    let hud = HUDController()
    private let permissions = PermissionsService()
    private let registry = EngineRegistry()
    private let prefs = Preferences.shared
    private var onboardingWindow: OnboardingWindowController?

    private static let onboardingKey = "didCompleteOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        audio.delegate = self
        hotkeys = HotkeyMonitor { [weak self] event in
            self?.handle(event)
        }
        showOnboardingIfNeeded()
    }

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingKey) else { return }
        let state = OnboardingState(permissions: permissions)
        let controller = OnboardingWindowController(state: state) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        onboardingWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func currentInjector() -> TextInjector {
        permissions.refreshAccessibility()
        return TextInjector(mode: permissions.accessibility ? .accessibilityPaste : .clipboardOnly)
    }

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .startCapture:
            do {
                try audio.start()
                hud.show(near: NSEvent.mouseLocation)
                hud.state.beginListening()
            } catch {
                print("audio.start failed: \(error)")
                hud.state.resetToIdle()
            }
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
        Task { @MainActor [weak self] in self?.hud.state.level = rms }
    }

    nonisolated func audioCapture(_ capture: AudioCapture,
                                  finishedWith samples: [Float],
                                  sampleRate: Double) {
        DispatchQueue.global(qos: .utility).async {
            let url = AppPaths.support.appendingPathComponent("last-recording.caf")
            try? WAVWriter.write(samples, sampleRate: sampleRate, to: url)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let engine = await MainActor.run { self.registry.active(prefs: self.prefs) }
                let result = try await engine.transcribe(
                    samples: samples,
                    sampleRate: sampleRate,
                    mode: .single(Locale(identifier: "pl-PL")))
                await MainActor.run {
                    let injector = self.currentInjector()
                    injector.insert(result.text)
                    self.hud.state.finish(preview: result.text.isEmpty ? "(brak tekstu)" : result.text)
                }
            } catch {
                await MainActor.run {
                    self.hud.state.finish(preview: "błąd: \(error)")
                }
                print("Transcription failed: \(error)")
            }
        }
    }
}
