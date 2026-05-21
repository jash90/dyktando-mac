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
        if prefs.hudEnabled {
            hud.show()
        }
        showOnboardingIfNeeded()
    }

    /// Public hook for Settings → General to flip HUD visibility live.
    func setHUDVisible(_ visible: Bool) {
        hud.setVisible(visible)
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
        let trusted = permissions.refreshAccessibility()
        NSLog("[App] currentInjector: AX trusted=%@ → mode=%@",
              trusted ? "true" : "false",
              trusted ? "accessibilityPaste" : "clipboardOnly")
        return TextInjector(mode: trusted ? .accessibilityPaste : .clipboardOnly)
    }

    /// Appends a clipboard-only hint to the HUD preview so the user knows the
    /// text was *only* copied (no automatic ⌘V) and why.
    private func annotate(_ preview: String, mode: TextInjector.Mode) -> String {
        switch mode {
        case .accessibilityPaste: return preview
        case .clipboardOnly:      return preview + "  ·  📋 wklej ⌘V (włącz Accessibility w Ustawieniach)"
        }
    }

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .startCapture(let kind):
            pendingCaptureKind = kind
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
        case .switchModel:
            break
        case .openSettings:
            SettingsWindowController.shared.show()
        case .openCommands:
            CommandsWindowController.shared.show()
        }
    }

    @objc func openCommands() {
        CommandsWindowController.shared.show()
    }

    /// Sends post-processed text through Gemma to decide whether it maps to
    /// a skill. Returns `true` if a skill was executed (so the caller skips
    /// the plain-text fallback), `false` otherwise. Errors fall through to
    /// the fallback rather than failing the whole utterance.
    @MainActor
    func tryAIRoute(text: String) async -> Bool {
        guard prefs.aiEnabled else { return false }
        guard let host = URL(string: prefs.ollamaHost) else { return false }
        let client = OllamaClient(host: host, model: prefs.ollamaModel)
        let router = IntentRouter(client: client)

        do {
            let decision = try await router.decide(text: text)
            switch decision {
            case .none:
                return false
            case .skill(let id, let params):
                guard let skill = SkillRegistry.skill(id: id) else {
                    NSLog("[AI] unknown skill '%@'", id)
                    return false
                }
                do {
                    let preview = try await skill.run(params: params)
                    self.hud.state.finish(preview: "🤖 \(preview)")
                    return true
                } catch {
                    NSLog("[AI] skill '%@' failed: %@", id, "\(error)")
                    self.hud.state.finish(preview: "🤖 błąd: \(error.localizedDescription)")
                    return true
                }
            }
        } catch {
            NSLog("[AI] router failed: %@", "\(error)")
            return false
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

        // Guard against empty / too-short recordings before hitting any engine.
        // SFSpeechRecognizer treats < ~250 ms of audio as "invalid audio data".
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
                    let polished = await MainActor.run {
                        PostprocessPipeline(mode: self.currentLanguageMode).apply(result.text)
                    }

                    // 1) Exact-match voice command (fast, deterministic).
                    let matched: Command? = await MainActor.run {
                        CommandStore.shared.match(polished)
                    }
                    if let cmd = matched {
                        await MainActor.run {
                            self.hud.state.finish(preview: "▶ \(cmd.name.isEmpty ? cmd.trigger : cmd.name)")
                        }
                        await CommandRunner().run(cmd)
                        return
                    }

                    // 2) AI routing via Gemma (Ollama) if enabled.
                    if await self.tryAIRoute(text: polished) {
                        return
                    }

                    // 3) Fallback: insert text into the foreground app.
                    await MainActor.run {
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
                        self.hud.state.finish(preview: self.annotate(polished, mode: injector.mode))
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
