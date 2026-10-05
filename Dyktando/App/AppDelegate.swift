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
    let meetings = MeetingRecorder.shared
    private var onboardingWindow: OnboardingWindowController?
    /// Ustawiane przy `.cancelCapture` — najbliższe nagranie trafia do kosza zamiast do modelu.
    private var discardNextRecording = false

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
        prewarmActiveEngine()
        let recovered = MeetingStore.shared.recoverInterrupted()
        if recovered > 0 { NSLog("[Meeting] recovered %d interrupted meeting(s)", recovered) }
        applyAudioRetention()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAudioRetention() }
        }
        MeetingDetector.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        meetings.stop()  // domknij pliki i meeting.json (stan „recorded”, nie „interrupted”)
        // Serwer MLX to osobny proces — nie zostawiamy go po zamknięciu aplikacji.
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await MLXSidecar.shared.stop()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    /// Model MLX ładuje się kilka–kilkadziesiąt sekund — robimy to w tle od razu po wyborze,
    /// żeby pierwsze dyktowanie nie czekało.
    func prewarmActiveEngine() {
        guard let engine = registry.active(prefs: prefs) as? MLXSidecarEngine else { return }
        let key = engine.variant.modelKey
        Task.detached(priority: .utility) {
            do {
                try await MLXSidecar.shared.prepare(model: key)
                NSLog("[App] prewarm %@ OK", key)
            } catch {
                NSLog("[App] prewarm %@ failed: %@", key, String(describing: error))
            }
        }
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

    // MARK: - Spotkania

    private var retentionTimer: Timer?

    private func applyAudioRetention() {
        let cleaned = MeetingStore.shared.applyRetention(days: prefs.meetingAudioRetentionDays)
        if cleaned > 0 { NSLog("[Meeting] retention: removed audio of %d meeting(s)", cleaned) }
    }

    @objc func toggleMeetingRecording() {
        if meetings.isRecording {
            if let meeting = meetings.stop() {
                hud.state.meetingStartedAt = nil
                hud.state.finish(preview: "Zapisano spotkanie (\(Self.clock(meeting.durationSeconds)))")
                if prefs.meetingAutoTranscribe { MeetingProcessing.shared.transcribe(meeting.id) }
            }
            return
        }
        meetings.start()
        guard meetings.isRecording else {
            hud.state.finish(preview: "Nie udało się nagrać: \(meetings.lastError ?? "nieznany błąd")")
            return
        }
        hud.state.meetingStartedAt = meetings.startedAt
        if prefs.hudEnabled { hud.show() }
        let note = meetings.systemAudioUnavailableReason.map { " · \($0)" } ?? ""
        hud.state.finish(preview: "Nagrywam spotkanie — poinformuj rozmówców o nagrywaniu\(note)")
    }

    nonisolated static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    private var didPromptAccessibility = false

    /// Wklejać tylko wtedy, gdy kursor jest w polu tekstowym (albo aplikacja nie mówi, co ma fokus).
    /// Bez uprawnienia Dostępności ⌘V i tak nie zadziała — wtedy tylko schowek + systemowa prośba o zgodę.
    private func pasteDecision() -> PasteDecision {
        let trusted = permissions.refreshAccessibility()
        guard trusted else {
            if !didPromptAccessibility {
                didPromptAccessibility = true
                permissions.promptAccessibility()
            }
            NSLog("[App] paste decision: no Accessibility → clipboard only")
            return .clipboardNoPermission
        }
        let (kind, snap) = FocusInspector.current()
        NSLog("[App] focus: app=%@ role=%@ subrole=%@ settable=%@ axError=%@ → %@",
              snap.bundleID ?? "?", snap.role ?? "-", snap.subrole ?? "-",
              snap.valueSettable ? "yes" : "no", snap.axError.map(String.init) ?? "-", String(describing: kind))
        return PasteDecision.decide(accessibilityTrusted: true, focus: kind)
    }

    /// Dopisek w HUD, gdy tekst został tylko w schowku — żeby było wiadomo dlaczego.
    private func annotate(_ preview: String, decision: PasteDecision) -> String {
        switch decision {
        case .paste:                 return preview
        case .clipboardNoTextField:  return preview + "  ·  📋 w schowku — kursor nie był w polu tekstowym (⌘V)"
        case .clipboardNoPermission: return preview + "  ·  📋 wklej ⌘V (włącz Dostępność dla Dyktando w Ustawieniach systemowych)"
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
        case .cancelCapture:
            discardNextRecording = true
            audio.stop()
            hud.state.resetToIdle()
        case .openSettings:
            SettingsWindowController.shared.show()
        case .toggleMeeting:
            toggleMeetingRecording()
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

        let minSamples = Int(sampleRate * 0.3)   // 300 ms
        Task { [weak self] in
            guard let self else { return }
            // Anulowane nagranie (modyfikator użyty jako część skrótu) — odrzuć po cichu.
            let discard = await MainActor.run { () -> Bool in
                guard self.discardNextRecording else { return false }
                self.discardNextRecording = false
                self.hud.state.resetToIdle()
                return true
            }
            if discard { return }


            // Guard against empty / too-short recordings before hitting the engine.
            guard samples.count >= minSamples else {
                print("[App] Skipping transcription: only \(samples.count) samples (need >= \(minSamples))")
                await MainActor.run { self.hud.state.finish(preview: "Za krótko — przytrzymaj klawisz dłużej") }
                return
            }

            // Dopiero po sprawdzeniu długości: krótkie stuknięcie to „za krótko”, nie problem z uprawnieniami.
            if AudioDiagnostics.isDigitalSilence(samples) {
                NSLog("[App] recording is digital silence (%d samples) — microphone access blocked?", samples.count)
                await MainActor.run { self.hud.state.finish(preview: AudioDiagnostics.digitalSilenceMessage) }
                return
            }

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
                    let decision = self.pasteDecision()
                    let injector = TextInjector(mode: decision == .paste ? .accessibilityPaste : .clipboardOnly)
                    injector.insert(polished)
                    let preview = polished.isEmpty ? "(brak tekstu)" : polished
                    self.hud.state.finish(preview: self.annotate(preview, decision: decision))
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
