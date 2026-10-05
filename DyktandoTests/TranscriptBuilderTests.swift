import AVFoundation
import XCTest
@testable import Dyktando

final class TranscriptBuilderTests: XCTestCase {
    private func u(_ start: Double, _ end: Double, _ track: Utterance.Track, _ text: String) -> Utterance {
        Utterance(start: start, end: end, track: track, text: text)
    }

    func test_systemUtterances_getSpeakerNumbersInOrderOfAppearance() {
        let system = [u(10, 14, .system, "druga"), u(0, 4, .system, "pierwsza"), u(20, 24, .system, "trzecia")]
        let speakers = [SpeakerSegment(speakerID: "S7", start: 0, end: 5),
                        SpeakerSegment(speakerID: "S2", start: 9, end: 15),
                        SpeakerSegment(speakerID: "S7", start: 19, end: 25)]
        let labeled = TranscriptBuilder.labelSystemUtterances(system, speakers: speakers)
        XCTAssertEqual(labeled.map(\.speaker), ["Rozmówca 1", "Rozmówca 2", "Rozmówca 1"])
        XCTAssertEqual(labeled.map(\.text), ["pierwsza", "druga", "trzecia"])
    }

    func test_withoutDiarization_everyoneIsRozmowcy() {
        let labeled = TranscriptBuilder.labelSystemUtterances([u(0, 2, .system, "x")], speakers: nil)
        XCTAssertEqual(labeled.first?.speaker, "Rozmówcy")
    }

    func test_largestOverlapWins() {
        let speakers = [SpeakerSegment(speakerID: "A", start: 0, end: 1),
                        SpeakerSegment(speakerID: "B", start: 1, end: 4)]
        let labeled = TranscriptBuilder.labelSystemUtterances([u(0, 4, .system, "x")], speakers: speakers)
        XCTAssertEqual(labeled.first?.speaker, "Rozmówca 1")  // B ma 3 s nakładania vs 1 s
    }

    func test_echoFromSpeakersIntoMic_isRemoved() {
        let system = [u(5, 9, .system, "Spotkanie przesuwamy na czwartek po południu")]
        let mic = [u(5.1, 9.2, .mic, "spotkanie przesuwamy na czwartek południu"),   // echo
                   u(12, 14, .mic, "Dobrze, pasuje mi czwartek")]                   // moja odpowiedź
        let kept = TranscriptBuilder.removeEcho(mic: mic, system: system)
        XCTAssertEqual(kept.map(\.text), ["Dobrze, pasuje mi czwartek"])
    }

    func test_overlappingButDifferentText_isNotEcho() {
        let system = [u(0, 4, .system, "Jaki jest termin wdrożenia projektu")]
        let mic = [u(1, 3, .mic, "Zaraz sprawdzę harmonogram")]
        XCTAssertEqual(TranscriptBuilder.removeEcho(mic: mic, system: system).count, 1)
    }

    func test_consecutiveSameSpeaker_isMerged() {
        var a = u(0, 3, .mic, "Pierwsze zdanie."); a.speaker = "Ja"
        var b = u(4, 6, .mic, "Drugie zdanie."); b.speaker = "Ja"
        var c = u(6.5, 8, .system, "Odpowiedź."); c.speaker = "Rozmówca 1"
        var d = u(20, 22, .mic, "Po przerwie."); d.speaker = "Ja"
        let merged = TranscriptBuilder.mergeConsecutive([d, c, b, a])
        XCTAssertEqual(merged.map(\.text), ["Pierwsze zdanie. Drugie zdanie.", "Odpowiedź.", "Po przerwie."])
        XCTAssertEqual(merged.first?.end, 6)
    }

    func test_markdown() {
        var a = u(3725, 3730, .mic, "Podsumujmy."); a.speaker = "Ja"
        let doc = TranscriptDocument(meetingID: "x", engine: "Parakeet TDT v3", createdAt: Date(), durationSeconds: 3_800, utterances: [a])
        let md = TranscriptBuilder.markdown(doc, startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(md.contains("[01:02:05] **Ja:** Podsumujmy."), md)
        XCTAssertTrue(md.contains("Model: Parakeet TDT v3"))
        XCTAssertTrue(md.contains("Mówcy: Ja"))
    }

    // MARK: - Integracja (opt-in): syntetyczne spotkanie z prawdziwych nagrań PL

    /// TEST_RUNNER_DYKTANDO_MEETING_E2E=1 — buduje spotkanie: ścieżka „system” = naprzemiennie głos
    /// kobiecy i męski z FLEURS, ścieżka „mic” = zdanie testowe; transkrypcja Parakeetem + diaryzacja.
    func test_e2e_syntheticMeeting_twoRemoteSpeakersAndMe() async throws {
        guard ProcessInfo.processInfo.environment["DYKTANDO_MEETING_E2E"] == "1" else {
            throw XCTSkip("ustaw TEST_RUNNER_DYKTANDO_MEETING_E2E=1")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let woman = home.appendingPathComponent("Projects/lektor/voices/fleurs_kobieta.wav")
        let man = home.appendingPathComponent("Projects/lektor/voices/fleurs_mezczyzna.wav")
        guard FileManager.default.fileExists(atPath: woman.path), FileManager.default.fileExists(atPath: man.path) else {
            throw XCTSkip("brak próbek głosów FLEURS")
        }
        func load(_ url: URL) throws -> [Float] {
            let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
            try f.read(into: b)
            return MonoResampler().convert(b)
        }
        let w = try load(woman), m = try load(man), me = try TestFixtures.polishThreeSeconds()
        let gap = [Float](repeating: 0.00001, count: 32_000)  // 2 s „ciszy w pokoju”, nie cyfrowe zero

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        var meeting = try store.create(startedAt: Date(), hasSystemAudio: true)
        let audio = store.audioFolder(for: meeting.id)
        let system = SegmentedAudioWriter(directory: audio, prefix: Meeting.systemPrefix)
        let mic = SegmentedAudioWriter(directory: audio, prefix: Meeting.micPrefix)
        // system: K, M, K, M; mic: „ja” w przerwach
        var systemTrack: [Float] = [], micTrack: [Float] = []
        for (i, voice) in [w, m, w, m].enumerated() {
            systemTrack += voice + gap
            micTrack += [Float](repeating: 0.00001, count: voice.count)
            if i == 1 {  // moja wypowiedź w środku
                systemTrack += [Float](repeating: 0.00001, count: me.count) + gap
                micTrack += gap + me + gap
            } else {
                micTrack += gap
            }
        }
        // TEST_RUNNER_DYKTANDO_MEETING_E2E_MINUTES=60 — powtórz wzorzec rozmowy do zadanej długości (pomiar czasu).
        if let minutes = Double(ProcessInfo.processInfo.environment["DYKTANDO_MEETING_E2E_MINUTES"] ?? "") {
            let target = Int(minutes * 60 * 16_000)
            let (s0, m0) = (systemTrack, micTrack)
            while systemTrack.count < target { systemTrack += s0; micTrack += m0 }
        }
        system.append(systemTrack); mic.append(micTrack)
        system.finish(); mic.finish()
        meeting.state = .recorded
        try store.save(meeting)

        let started = Date()
        let options = MeetingTranscriber.Options(engine: ParakeetEngine(),
                                                 languageMode: .single(Locale(identifier: "pl-PL")), diarize: true)
        let doc = try await MeetingTranscriber().transcribe(meetingID: meeting.id, store: store, options: options) { _, _ in }
        let elapsed = Date().timeIntervalSince(started)
        print("[e2e] \(String(format: "%.0f", doc.durationSeconds)) s nagrania w \(String(format: "%.1f", elapsed)) s; mówcy: \(doc.speakers)")
        for line in doc.utterances.prefix(8) { print("[e2e] [\(TranscriptBuilder.timestamp(line.start))] \(line.speaker): \(line.text)") }

        XCTAssertTrue(doc.speakers.contains("Ja"), "\(doc.speakers)")
        XCTAssertEqual(Set(doc.speakers.filter { $0.hasPrefix("Rozmówca") }).count, 2, "oczekiwane 2 głosy: \(doc.speakers)")
        XCTAssertEqual(store.load(meeting.id)?.state, .transcribed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.transcriptURL(for: meeting.id).path))
    }
}
