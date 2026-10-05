import Foundation

/// Kolejka przetwarzania spotkań w tle (transkrypcja; w etapie 3 także podsumowanie) —
/// stan dla menu, HUD i okna spotkań, z możliwością przerwania.
@MainActor
final class MeetingProcessing: ObservableObject {
    static let shared = MeetingProcessing()

    struct Job: Equatable {
        var meetingID: String
        var progress: Double
        var status: String
    }

    @Published private(set) var jobs: [String: Job] = [:]
    @Published private(set) var lastFinished: (id: String, message: String)?
    private var tasks: [String: Task<Void, Never>] = [:]

    var active: Job? { jobs.values.sorted { $0.meetingID < $1.meetingID }.first }

    func transcribe(_ meetingID: String, engineID: EngineID? = nil) {
        guard tasks[meetingID] == nil else { return }
        let prefs = Preferences.shared
        let id = engineID ?? EngineID(rawValue: prefs.meetingEngineID) ?? .parakeetTDTv3
        let options = MeetingTranscriber.Options(engine: EngineRegistry.makeEngine(id),
                                                 languageMode: LanguageModeCodec.decode(prefs.languageModeRaw),
                                                 diarize: prefs.meetingDiarization)
        jobs[meetingID] = Job(meetingID: meetingID, progress: 0, status: "Przygotowanie")
        tasks[meetingID] = Task { [weak self] in
            let started = Date()
            do {
                let doc = try await MeetingTranscriber.shared.transcribe(meetingID: meetingID, options: options) { fraction, status in
                    Task { @MainActor in self?.jobs[meetingID]?.progress = fraction; self?.jobs[meetingID]?.status = status }
                }
                let seconds = Date().timeIntervalSince(started)
                NSLog("[Meeting] transcribed %@: %d wypowiedzi, %.0f s audio w %.0f s", meetingID, doc.utterances.count,
                      doc.durationSeconds, seconds)
                self?.finish(meetingID, message: "Transkrypt gotowy (\(doc.utterances.count) wypowiedzi, \(AppDelegate.clock(seconds)))")
                if Preferences.shared.meetingAutoSummarize { self?.summarize(meetingID) }
            } catch is CancellationError {
                self?.finish(meetingID, message: "Transkrypcja przerwana")
            } catch {
                NSLog("[Meeting] transcription %@ failed: %@", meetingID, String(describing: error))
                self?.finish(meetingID, message: "Transkrypcja nie powiodła się: \(error.localizedDescription)")
            }
        }
    }

    /// Podsumowanie przez zewnętrznego dostawcę AI (transkrypt opuszcza Maca — tylko na żądanie
    /// albo gdy użytkownik włączył automatyczne podsumowania).
    func summarize(_ meetingID: String, provider: AIProviderID? = nil) {
        guard tasks[meetingID] == nil else { return }
        let store = MeetingStore.shared
        let providerID = provider ?? AISettings.defaultProvider
        guard let meeting = store.load(meetingID),
              let transcript = try? String(contentsOf: store.transcriptURL(for: meetingID), encoding: .utf8) else {
            finish(meetingID, message: "Najpierw przepisz spotkanie — brak transkryptu.")
            return
        }
        let config: LLMConfig
        do { config = try AISettings.config(for: providerID) } catch {
            finish(meetingID, message: error.localizedDescription)
            return
        }
        let prompt = AISettings.prompt
        jobs[meetingID] = Job(meetingID: meetingID, progress: 0, status: "Podsumowanie (\(providerID.displayName))")
        tasks[meetingID] = Task { [weak self] in
            var m = meeting
            let previous = m.state
            m.state = .summarizing
            try? store.save(m)
            do {
                let summarizer = MeetingSummarizer(provider: config.makeProvider(), config: config)
                let summary = try await summarizer.summarize(transcript: transcript, prompt: prompt) { fraction, status in
                    Task { @MainActor in self?.jobs[meetingID]?.progress = fraction; self?.jobs[meetingID]?.status = status }
                }
                _ = try MeetingSummarizer.save(summary, meeting: m, config: config, store: store)
                m.state = .summarized
                m.lastError = nil
                try? store.save(m)
                self?.finish(meetingID, message: "Podsumowanie gotowe (\(providerID.displayName))")
            } catch is CancellationError {
                m.state = previous
                try? store.save(m)
                self?.finish(meetingID, message: "Podsumowanie przerwane")
            } catch {
                m.state = previous
                m.lastError = error.localizedDescription
                try? store.save(m)
                NSLog("[Meeting] summary %@ failed: %@", meetingID, error.localizedDescription)
                self?.finish(meetingID, message: "Podsumowanie nie powiodło się: \(error.localizedDescription)")
            }
        }
    }

    func cancel(_ meetingID: String) {
        tasks[meetingID]?.cancel()
    }

    private func finish(_ meetingID: String, message: String) {
        tasks[meetingID] = nil
        jobs[meetingID] = nil
        lastFinished = (meetingID, message)
        AppDelegate.shared?.hud.state.finish(preview: message)
    }
}
