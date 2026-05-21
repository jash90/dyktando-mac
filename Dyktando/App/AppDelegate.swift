import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyMonitor?
    private let audio = AudioCapture()
    let hud = HUDController()
    private let permissions = PermissionsService()
    private let registry = EngineRegistry.shared
    private let prefs = Preferences.shared
    private var onboardingWindow: OnboardingWindowController?

    var sharedRegistry: EngineRegistry { registry }

    private static let onboardingKey = "didCompleteOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        audio.delegate = self
        hotkeys = HotkeyMonitor { [weak self] event in
            self?.handle(event)
        }
        if prefs.hudEnabled {
            hud.show()
        }
        showOnboardingIfNeeded()
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    /// Public hook for Settings → General to flip HUD visibility live.
    func setHUDVisible(_ visible: Bool) {
        hud.setVisible(visible)
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

    private var currentLanguageMode: LanguageMode {
        LanguageModeCodec.decode(prefs.languageModeRaw)
    }

    private func currentInjector() -> TextInjector {
        let trusted = permissions.refreshAccessibility()
        NSLog("[App] currentInjector: AX trusted=%@ → mode=%@",
              trusted ? "true" : "false",
              trusted ? "accessibilityPaste" : "clipboardOnly")
        return TextInjector(mode: trusted ? .accessibilityPaste : .clipboardOnly)
    }

    /// Appends a clipboard-only hint to the HUD preview so the user knows the
    /// text was only copied (no automatic ⌘V) and why.
    private func annotate(_ preview: String, mode: TextInjector.Mode) -> String {
        switch mode {
        case .accessibilityPaste: return preview
        case .clipboardOnly:      return preview + "  ·  📋 wklej ⌘V (włącz Accessibility w Ustawieniach)"
        }
    }

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .startCapture:
            do {
                try audio.start()
                if prefs.hudEnabled { hud.show() }
                hud.state.beginListening()
            } catch {
                let ns = error as NSError
                let detail = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
                print("audio.start failed: \(detail)")
                hud.state.resetToIdle()
                let alert = NSAlert()
                alert.messageText = "Nie udało się uruchomić mikrofonu"
                alert.informativeText = """
                \(detail)

                Najczęstsze przyczyny:
                • Brak uprawnień do Mikrofonu — sprawdź Ustawienia systemowe → \
                Prywatność i bezpieczeństwo → Mikrofon i włącz Dyktando.
                • Inne urządzenie używa mikrofonu (np. spotkanie video).
                • Brak urządzenia wejściowego — podłącz mikrofon lub wybierz w \
                Ustawieniach systemowych → Dźwięk → Wejście.
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Otwórz Ustawienia Prywatności")
                alert.addButton(withTitle: "Zamknij")
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .stopCapture:
            audio.stop()
            hud.state.beginTranscribing()
        case .openSettings:
            SettingsWindowController.shared.show()
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

        // Guard against empty / too-short recordings before hitting the engine.
        let minSamples = Int(sampleRate * 0.3)   // 300 ms
        guard samples.count >= minSamples else {
            print("[App] Skipping transcription: only \(samples.count) samples (need >= \(minSamples))")
            Task { @MainActor [weak self] in
                self?.hud.state.finish(preview: "Za krótko — przytrzymaj F5 dłużej")
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let (engine, mode) = await MainActor.run {
                    (self.registry.active(prefs: self.prefs), self.currentLanguageMode)
                }
                let result = try await engine.transcribe(
                    samples: samples,
                    sampleRate: sampleRate,
                    mode: mode)
                await MainActor.run {
                    let pipeline = PostprocessPipeline(mode: self.currentLanguageMode)
                    let polished = pipeline.apply(result.text)
                    let injector = self.currentInjector()
                    injector.insert(polished)
                    let preview = polished.isEmpty ? "(brak tekstu)" : polished
                    self.hud.state.finish(preview: self.annotate(preview, mode: injector.mode))
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
