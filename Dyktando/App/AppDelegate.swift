import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyMonitor?
    private let audio = AudioCapture()
    let hud = HUDController()
    private let permissions = PermissionsService()
    private let registry = EngineRegistry()
    private let prefs = Preferences.shared
    private var onboardingWindow: OnboardingWindowController?
    private var pendingCaptureKind: CaptureKind = .singleEngine
    private let stats = ComparisonStats()

    var sharedRegistry: EngineRegistry { registry }

    private static let onboardingKey = "didCompleteOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        audio.delegate = self
        hotkeys = HotkeyMonitor { [weak self] event in
            self?.handle(event)
        }
        showOnboardingIfNeeded()
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
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
        permissions.refreshAccessibility()
        return TextInjector(mode: permissions.accessibility ? .accessibilityPaste : .clipboardOnly)
    }

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .startCapture(let kind):
            pendingCaptureKind = kind
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
        case .switchModel:
            break
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

        Task { [weak self] in
            guard let self else { return }
            let kind = await MainActor.run { self.pendingCaptureKind }
            switch kind {
            case .singleEngine:
                do {
                    let (engine, mode) = await MainActor.run {
                        (self.registry.active(prefs: self.prefs), self.currentLanguageMode)
                    }
                    let result = try await engine.transcribe(
                        samples: samples,
                        sampleRate: sampleRate,
                        mode: mode)
                    await MainActor.run {
                        let injector = self.currentInjector()
                        let pipeline = PostprocessPipeline(mode: self.currentLanguageMode)
                        let polished = pipeline.apply(result.text)
                        injector.insert(polished)
                        self.hud.state.finish(preview: polished.isEmpty ? "(brak tekstu)" : polished)
                    }
                } catch {
                    await MainActor.run {
                        self.hud.state.finish(preview: "błąd: \(error)")
                    }
                    print("Transcription failed: \(error)")
                }
            case .comparison:
                let (engines, compMode) = await MainActor.run {
                    (Array(self.registry.engines.values), self.currentLanguageMode)
                }
                let router = TranscriptionRouter(engines: engines)
                let rows = await router.routeAll(samples: samples,
                                                 sampleRate: sampleRate,
                                                 mode: compMode)
                await MainActor.run {
                    ComparisonWindowController.shared.show(rows: rows) { [weak self] chosen in
                        guard let self else { return }
                        let injector = self.currentInjector()
                        let pipeline = PostprocessPipeline(mode: self.currentLanguageMode)
                        let polished = pipeline.apply(chosen.result.text)
                        injector.insert(polished)
                        self.hud.state.finish(preview: polished)
                        Task {
                            await self.stats.record(chosen: chosen.engineID,
                                                    language: chosen.result.language)
                            if let nudge = await self.stats.nudgeIfApplicable(for: chosen.result.language) {
                                await MainActor.run {
                                    NudgeAlert.askToSetDefault(engine: nudge.winner,
                                                               winRate: nudge.winRate,
                                                               prefs: self.prefs)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
