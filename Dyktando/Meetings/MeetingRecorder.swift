import Foundation

/// Nagrywanie spotkania: dwie ścieżki (mikrofon + dźwięk systemowy) zapisywane na bieżąco na dysk.
@MainActor
final class MeetingRecorder: ObservableObject {
    static let shared = MeetingRecorder()

    @Published private(set) var current: Meeting?
    @Published private(set) var startedAt: Date?
    @Published private(set) var systemAudioUnavailableReason: String?
    @Published private(set) var lastError: String?

    var isRecording: Bool { current != nil }

    private let store: MeetingStore
    private var micWriter: SegmentedAudioWriter?
    private var systemWriter: SegmentedAudioWriter?
    private var mic: MicTrackRecorder?
    private var system: AnyObject?          // SystemAudioRecorder (macOS 14.4+)
    private var autosave: Timer?
    private var tapWatchdog: Timer?
    private var tapRestarts = 0

    init(store: MeetingStore = .shared) { self.store = store }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard !isRecording else { return }
        lastError = nil
        systemAudioUnavailableReason = nil
        let now = Date()
        var createdID: String?
        do {
            var meeting = try store.create(startedAt: now, hasSystemAudio: false)
            createdID = meeting.id
            let audio = store.audioFolder(for: meeting.id)

            let micWriter = SegmentedAudioWriter(directory: audio, prefix: Meeting.micPrefix)
            let mic = MicTrackRecorder(writer: micWriter)
            try mic.start()
            self.micWriter = micWriter
            self.mic = mic

            if #available(macOS 14.4, *) {
                let systemWriter = SegmentedAudioWriter(directory: audio, prefix: Meeting.systemPrefix)
                let system = SystemAudioRecorder(writer: systemWriter)
                do {
                    try system.start()
                    self.systemWriter = systemWriter
                    self.system = system
                    meeting.hasSystemAudio = true
                } catch {
                    systemAudioUnavailableReason = error.localizedDescription
                    NSLog("[Meeting] system audio unavailable: %@", String(describing: error))
                }
            } else {
                systemAudioUnavailableReason = "Dźwięk z aplikacji wymaga macOS 14.4 lub nowszego — nagrywam tylko mikrofon."
            }

            try store.save(meeting)
            current = meeting
            startedAt = now
            autosave = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveProgress() }
            }
            tapRestarts = 0
            if meeting.hasSystemAudio {
                tapWatchdog = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reviveDeadTap() }
                }
            }
            NSLog("[Meeting] recording started: %@ (system audio: %@)", meeting.id, meeting.hasSystemAudio ? "yes" : "no")
        } catch {
            lastError = error.localizedDescription
            NSLog("[Meeting] start failed: %@", String(describing: error))
            teardown()
            // Folder z meeting.json w stanie „recording” byłby fantomem nie do usunięcia z listy.
            if let createdID { try? store.delete(createdID) }
        }
    }

    /// Zatrzymuje nagrywanie i zwraca zapisane spotkanie.
    @discardableResult
    func stop() -> Meeting? {
        guard var meeting = current else { return nil }
        teardown()
        meeting.durationSeconds = store.recordedSeconds(for: meeting.id)
        meeting.endedAt = Date()
        meeting.state = .recorded
        try? store.save(meeting)
        current = nil
        startedAt = nil
        NSLog("[Meeting] recording stopped: %@ (%.0f s)", meeting.id, meeting.durationSeconds)
        return meeting
    }

    /// Dźwięk systemowy podejrzanie cichy od dłuższego czasu (brak zgody albo nic nie gra).
    var systemSilentSeconds: Double {
        if #available(macOS 14.4, *), let system = system as? SystemAudioRecorder {
            return system.consecutiveSilentSeconds
        }
        return 0
    }

    /// Tap utworzony przed udzieleniem zgody nie oddaje żadnych buforów do końca życia —
    /// tworzymy go od nowa (ten sam writer, więc ścieżka się nie rozjeżdża w plikach).
    private func reviveDeadTap() {
        guard #available(macOS 14.4, *), let system = system as? SystemAudioRecorder else { return }
        if system.buffersReceived > 0 {
            tapWatchdog?.invalidate()
            tapWatchdog = nil
            return
        }
        guard tapRestarts < 5, let writer = systemWriter else {
            systemAudioUnavailableReason = "Brak dźwięku z aplikacji — sprawdź zgodę „Nagrywanie dźwięku systemowego” dla Dyktando."
            tapWatchdog?.invalidate()
            tapWatchdog = nil
            return
        }
        tapRestarts += 1
        system.stop()
        // Martwy tap nie zapisał nic — dopełnij ścieżkę ciszą do długości mikrofonu, żeby czasy
        // rozmówców nie przesunęły się o czas, w którym użytkownik udzielał zgody.
        let gap = Self.alignmentPadding(reference: micWriter?.samplesWritten ?? 0, track: writer.samplesWritten)
        if gap > 0 { writer.append([Float](repeating: 0, count: gap)) }
        let fresh = SystemAudioRecorder(writer: writer)
        do {
            try fresh.start()
            self.system = fresh
            NSLog("[Meeting] system tap had no buffers — recreated (attempt %d)", tapRestarts)
        } catch {
            NSLog("[Meeting] system tap recreate failed: %@", String(describing: error))
        }
    }

    /// Ile próbek ciszy dopisać do ścieżki, żeby zrównała się z referencyjną (mikrofonem).
    nonisolated static func alignmentPadding(reference: Int, track: Int) -> Int {
        max(0, reference - track)
    }

    private func saveProgress() {
        guard var meeting = current else { return }
        meeting.durationSeconds = max(micWriter?.secondsWritten ?? 0, systemWriter?.secondsWritten ?? 0)
        try? store.save(meeting)
    }

    private func teardown() {
        autosave?.invalidate()
        autosave = nil
        tapWatchdog?.invalidate()
        tapWatchdog = nil
        mic?.stop()
        if #available(macOS 14.4, *) { (system as? SystemAudioRecorder)?.stop() }
        micWriter?.finish()
        systemWriter?.finish()
        mic = nil
        system = nil
        micWriter = nil
        systemWriter = nil
    }
}
