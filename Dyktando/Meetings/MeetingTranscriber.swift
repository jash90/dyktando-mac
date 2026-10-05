import FluidAudio
import Foundation

/// Transkrypcja nagranego spotkania: VAD dzieli każdą ścieżkę na wypowiedzi (z ich czasami),
/// każda wypowiedź idzie przez wybrany silnik (Parakeet / Canary / Whisper — ten sam interfejs),
/// ścieżka „system” przechodzi diaryzację (kto z rozmówców mówi), a `TranscriptBuilder` składa całość.
/// Pamięć ograniczona: audio czytane fragmentami z plików segmentów.
actor MeetingTranscriber {
    struct Options: Sendable {
        var engine: TranscriptionEngine
        var languageMode: LanguageMode
        var diarize: Bool
    }

    /// (postęp 0…1, opis etapu)
    typealias Progress = @Sendable (Double, String) -> Void

    static let shared = MeetingTranscriber()

    /// VAD liczony oknami po ~10 min (wielokrotność porcji modelu 4096 próbek), nie całością w RAM.
    static let vadWindowSamples = VadManager.chunkSize * 2_343

    private var vad: VadManager?
    private var diarizer: OfflineDiarizerManager?

    func transcribe(meetingID: String, store: MeetingStore = .shared, options: Options,
                    progress: @escaping Progress) async throws -> TranscriptDocument {
        guard var meeting = store.load(meetingID) else {
            throw NSError(domain: "Dyktando.Meeting", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nie ma takiego spotkania."])
        }
        guard !meeting.audioDeleted else {
            throw NSError(domain: "Dyktando.Meeting", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio tego spotkania zostało już usunięte."])
        }
        let previousState = meeting.state
        meeting.state = .transcribing
        try? store.save(meeting)
        do {
            let doc = try await run(meeting: meeting, store: store, options: options, progress: progress)
            meeting.state = .transcribed
            meeting.transcriptEngine = options.engine.displayName
            meeting.lastError = nil
            try store.save(meeting)
            return doc
        } catch {
            meeting.state = error is CancellationError ? previousState : .failed
            meeting.lastError = error is CancellationError ? nil : error.localizedDescription
            try? store.save(meeting)
            throw error
        }
    }

    private func run(meeting: Meeting, store: MeetingStore, options: Options, progress: @escaping Progress) async throws -> TranscriptDocument {
        let audio = store.audioFolder(for: meeting.id)
        let micSamples = SegmentedAudioReader.totalSamples(in: audio, prefix: Meeting.micPrefix)
        let systemSamples = SegmentedAudioReader.totalSamples(in: audio, prefix: Meeting.systemPrefix)
        let duration = Double(max(micSamples, systemSamples)) / MonoResampler.sampleRate

        progress(0.01, "Wykrywanie mowy")
        let vad = try await loadVAD()
        let micSegments = try await speechSegments(vad: vad, audio: audio, prefix: Meeting.micPrefix, total: micSamples)
        let systemSegments = systemSamples > 0
            ? try await speechSegments(vad: vad, audio: audio, prefix: Meeting.systemPrefix, total: systemSamples) : []

        // Diaryzacja ma osobną wagę w pasku postępu, transkrypcja dzieli resztę po fragmentach.
        let shouldDiarize = options.diarize && !systemSegments.isEmpty
        let transcribeShare = shouldDiarize ? 0.75 : 0.95
        let total = max(1, micSegments.count + systemSegments.count)
        var done = 0

        func transcribeTrack(_ segments: [VadSegment], prefix: String, track: Utterance.Track) async throws -> [Utterance] {
            var out: [Utterance] = []
            for segment in segments {
                try Task.checkCancellation()
                let start = segment.startSample(sampleRate: Int(MonoResampler.sampleRate))
                let count = segment.endSample(sampleRate: Int(MonoResampler.sampleRate)) - start
                let samples = try SegmentedAudioReader.read(directory: audio, prefix: prefix, start: start, count: count)
                if !samples.isEmpty, !AudioDiagnostics.isDigitalSilence(samples) {
                    let result = try await options.engine.transcribe(samples: samples, sampleRate: MonoResampler.sampleRate,
                                                                     mode: options.languageMode)
                    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        out.append(Utterance(start: segment.startTime, end: segment.endTime, track: track, text: text))
                    }
                }
                done += 1
                progress(0.05 + transcribeShare * Double(done) / Double(total),
                         "Transkrypcja \(done)/\(total) wypowiedzi")
            }
            return out
        }

        let mic = try await transcribeTrack(micSegments, prefix: Meeting.micPrefix, track: .mic)
        let system = try await transcribeTrack(systemSegments, prefix: Meeting.systemPrefix, track: .system)

        var speakers: [SpeakerSegment]?
        if shouldDiarize {
            try Task.checkCancellation()
            progress(0.05 + transcribeShare, "Rozpoznawanie rozmówców")
            speakers = try await diarize(audio: audio, folder: store.folder(for: meeting.id)) { fraction in
                progress(0.05 + transcribeShare + (0.95 - transcribeShare) * fraction, "Rozpoznawanie rozmówców")
            }
        }

        let doc = TranscriptDocument(meetingID: meeting.id, engine: options.engine.displayName, createdAt: Date(),
                                     durationSeconds: duration,
                                     utterances: TranscriptBuilder.build(mic: mic, system: system, speakers: speakers))
        try write(doc, meeting: meeting, store: store)
        progress(1, "Gotowe")
        return doc
    }

    // MARK: - VAD

    private func loadVAD() async throws -> VadManager {
        if let vad { return vad }
        let fresh = try await VadManager()
        vad = fresh
        return fresh
    }

    private func speechSegments(vad: VadManager, audio: URL, prefix: String, total: Int) async throws -> [VadSegment] {
        guard total > 0 else { return [] }
        var results: [VadResult] = []
        var start = 0
        while start < total {
            try Task.checkCancellation()
            let count = min(Self.vadWindowSamples, total - start)
            let samples = try SegmentedAudioReader.read(directory: audio, prefix: prefix, start: start, count: count)
            results += try await vad.process(samples)
            start += count
        }
        return await vad.segmentSpeech(from: results, totalSamples: total)
    }

    // MARK: - Diaryzacja

    private func diarize(audio: URL, folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerSegment] {
        if diarizer == nil {
            let manager = OfflineDiarizerManager()
            try await manager.prepareModels()  // pierwszy raz: pobranie modeli (~kilkadziesiąt MB)
            diarizer = manager
        }
        // Diaryzator czyta plik z dysku (mapowany) — sklejamy ścieżkę „system” do jednego WAV.
        let wav = folder.appendingPathComponent(".system-diarization.wav")
        try SegmentedAudioReader.exportWAV(directory: audio, prefix: Meeting.systemPrefix, to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }
        let result = try await diarizer!.process(wav) { done, total in
            progress(total > 0 ? Double(done) / Double(total) : 0)
        }
        return result.segments.map {
            SpeakerSegment(speakerID: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
    }

    // MARK: - Zapis

    private func write(_ doc: TranscriptDocument, meeting: Meeting, store: MeetingStore) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(doc).write(to: store.transcriptJSONURL(for: meeting.id), options: .atomic)
        try TranscriptBuilder.markdown(doc, startedAt: meeting.startedAt)
            .write(to: store.transcriptURL(for: meeting.id), atomically: true, encoding: .utf8)
    }
}
