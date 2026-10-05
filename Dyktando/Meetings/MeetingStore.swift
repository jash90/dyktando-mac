import Foundation

/// Metadane spotkania zapisywane w `meeting.json` w folderze spotkania.
struct Meeting: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case recording      // trwa nagrywanie
        case interrupted    // aplikacja zamknęła się w trakcie nagrywania — pliki zostały
        case recorded       // nagranie zakończone
        case transcribing
        case transcribed
        case summarizing
        case summarized
        case failed
    }

    let id: String              // nazwa folderu: yyyy-MM-dd_HH-mm-ss
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Double
    var state: State
    var hasSystemAudio: Bool
    var title: String?
    var audioDeleted = false
    var transcriptEngine: String?
    var lastError: String?

    static let micPrefix = "mic"
    static let systemPrefix = "system"
}

/// Foldery spotkań w `Application Support/Dyktando/Meetings/`.
struct MeetingStore: Sendable {
    let root: URL

    static let shared = MeetingStore(root: AppPaths.support.appendingPathComponent("Meetings", isDirectory: true))

    func folder(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func audioFolder(for id: String) -> URL { folder(for: id).appendingPathComponent("audio", isDirectory: true) }
    func transcriptURL(for id: String) -> URL { folder(for: id).appendingPathComponent("transcript.md") }
    func transcriptJSONURL(for id: String) -> URL { folder(for: id).appendingPathComponent("transcript.json") }
    func summariesFolder(for id: String) -> URL { folder(for: id).appendingPathComponent("summaries", isDirectory: true) }
    private func metadataURL(for id: String) -> URL { folder(for: id).appendingPathComponent("meeting.json") }

    static func makeID(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: date)
    }

    func create(startedAt: Date, hasSystemAudio: Bool) throws -> Meeting {
        var id = Self.makeID(for: startedAt)
        var n = 2
        while FileManager.default.fileExists(atPath: folder(for: id).path) {
            id = Self.makeID(for: startedAt) + "-\(n)"
            n += 1
        }
        try FileManager.default.createDirectory(at: audioFolder(for: id), withIntermediateDirectories: true)
        let meeting = Meeting(id: id, startedAt: startedAt, endedAt: nil, durationSeconds: 0,
                              state: .recording, hasSystemAudio: hasSystemAudio)
        try save(meeting)
        return meeting
    }

    func save(_ meeting: Meeting) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(meeting).write(to: metadataURL(for: meeting.id), options: .atomic)
    }

    func load(_ id: String) -> Meeting? {
        guard let data = try? Data(contentsOf: metadataURL(for: id)) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Meeting.self, from: data)
    }

    /// Wszystkie spotkania, najnowsze pierwsze.
    func all() -> [Meeting] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return ids.compactMap(load).sorted { $0.startedAt > $1.startedAt }
    }

    /// Długość nagrania odczytana z plików (dłuższa z dwóch ścieżek).
    func recordedSeconds(for id: String) -> Double {
        let dir = audioFolder(for: id)
        let samples = max(SegmentedAudioReader.totalSamples(in: dir, prefix: Meeting.micPrefix),
                          SegmentedAudioReader.totalSamples(in: dir, prefix: Meeting.systemPrefix))
        return Double(samples) / MonoResampler.sampleRate
    }

    /// Po starcie aplikacji: spotkania w stanie `recording` (aplikacja padła / została zabita w trakcie)
    /// → `interrupted`, z długością odczytaną z plików. Zwraca liczbę odzyskanych.
    @discardableResult
    func recoverInterrupted() -> Int {
        var recovered = 0
        for var meeting in all() where meeting.state == .recording {
            let audio = audioFolder(for: meeting.id)
            for prefix in [Meeting.micPrefix, Meeting.systemPrefix] {
                for segment in SegmentedAudioReader.segmentURLs(in: audio, prefix: prefix) {
                    do { try SegmentedAudioReader.repair(segment) } catch {
                        NSLog("[Meeting] repair %@ failed: %@", segment.lastPathComponent, String(describing: error))
                    }
                }
            }
            meeting.state = .interrupted
            meeting.durationSeconds = recordedSeconds(for: meeting.id)
            meeting.endedAt = meeting.startedAt.addingTimeInterval(meeting.durationSeconds)
            try? save(meeting)
            recovered += 1
        }
        // Aplikacja zamknięta w trakcie transkrypcji / podsumowania — przywróć stan wynikający z plików.
        for var meeting in all() where meeting.state == .transcribing || meeting.state == .summarizing {
            let hasTranscript = FileManager.default.fileExists(atPath: transcriptURL(for: meeting.id).path)
            let hasSummary = MeetingSummarizer.latest(for: meeting.id, store: self) != nil
            meeting.state = hasSummary ? .summarized : hasTranscript ? .transcribed : .recorded
            try? save(meeting)
            recovered += 1
        }
        return recovered
    }

    /// Retencja: usuwa audio spotkań starszych niż `days` dni — tylko tych już przepisanych
    /// (usunięcie nieprzepisanego nagrania byłoby utratą danych). Zwraca liczbę spotkań.
    @discardableResult
    func applyRetention(days: Int, now: Date = Date()) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var cleaned = 0
        for var meeting in all()
        where !meeting.audioDeleted && meeting.state != .recording && meeting.state != .transcribing
            && (meeting.endedAt ?? meeting.startedAt) < cutoff
            && FileManager.default.fileExists(atPath: transcriptURL(for: meeting.id).path) {
            try? FileManager.default.removeItem(at: audioFolder(for: meeting.id))
            meeting.audioDeleted = true
            try? save(meeting)
            cleaned += 1
        }
        return cleaned
    }

    func delete(_ id: String) throws {
        try FileManager.default.removeItem(at: folder(for: id))
    }
}
