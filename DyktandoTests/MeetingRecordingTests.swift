import AVFoundation
import XCTest
@testable import Dyktando

final class MeetingRecordingTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func sine(seconds: Double, freq: Float = 440, rate: Double = 16_000) -> [Float] {
        (0..<Int(seconds * rate)).map { 0.3 * sin(2 * .pi * freq * Float($0) / Float(rate)) }
    }

    // MARK: SegmentedAudioWriter

    func test_writer_rotatesSegmentsAndKeepsAllSamples() throws {
        let writer = SegmentedAudioWriter(directory: tmp, prefix: "mic", segmentSeconds: 0.5)
        let signal = sine(seconds: 1.3)
        // w kawałkach, jak z tapu audio
        stride(from: 0, to: signal.count, by: 1024).forEach { writer.append(Array(signal[$0 ..< min($0 + 1024, signal.count)])) }
        writer.finish()

        XCTAssertNil(writer.lastError)
        XCTAssertEqual(writer.segments, ["mic-000.caf", "mic-001.caf", "mic-002.caf"])
        XCTAssertEqual(writer.samplesWritten, signal.count)
        XCTAssertEqual(SegmentedAudioReader.totalSamples(in: tmp, prefix: "mic"), signal.count)

        // fragment przez granicę plików (0.5 s = 8000 próbek)
        let piece = try SegmentedAudioReader.read(directory: tmp, prefix: "mic", start: 7_000, count: 2_000)
        XCTAssertEqual(piece.count, 2_000)
        for (i, v) in piece.enumerated() {
            XCTAssertEqual(v, signal[7_000 + i], accuracy: 1.0 / 16_000, "próbka \(i)")  // 16-bit kwantyzacja
        }
    }

    func test_writer_ignoresAppendAfterFinish() {
        let writer = SegmentedAudioWriter(directory: tmp, prefix: "system", segmentSeconds: 10)
        writer.append(sine(seconds: 0.2))
        writer.finish()
        writer.append(sine(seconds: 0.2))
        XCTAssertEqual(writer.samplesWritten, 3_200)
    }

    func test_exportWAV_concatenatesSegments() throws {
        let writer = SegmentedAudioWriter(directory: tmp, prefix: "system", segmentSeconds: 0.25)
        writer.append(sine(seconds: 1.0))
        writer.finish()
        let wav = tmp.appendingPathComponent("system.wav")
        try SegmentedAudioReader.exportWAV(directory: tmp, prefix: "system", to: wav)
        let file = try AVAudioFile(forReading: wav)
        XCTAssertEqual(file.length, 16_000)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
    }

    // MARK: MonoResampler

    func test_resampler_convertsStereo48kToMono16k_repeatedly() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let resampler = MonoResampler()
        var total = 0
        var counts: [Int] = []
        for round in 0..<10 {  // regresja: `.endOfStream` w konwerterze dawał zera po pierwszym buforze
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
            buf.frameLength = 4_800
            for ch in 0..<2 {
                for i in 0..<4_800 { buf.floatChannelData![ch][i] = 0.3 * sin(2 * .pi * 440 * Float(i) / 48_000) }
            }
            let out = resampler.convert(buf)
            // Konwerter oddaje próbki porcjami (część zostaje w filtrze do następnego wywołania),
            // więc pojedynczy bufor bywa krótszy — liczy się, że żaden nie jest pusty i suma się zgadza.
            XCTAssertGreaterThan(out.count, 1_200, "bufor \(round)")
            counts.append(out.count)
            XCTAssertTrue(out.contains { abs($0) > 0.05 }, "wyjście nie może być ciszą")
            total += out.count
        }
        print("resampler counts: \(counts) total=\(total)")
        XCTAssertEqual(Double(total), 16_000, accuracy: 320)  // 10 × 0.1 s minus stałe opóźnienie filtra (≤ 20 ms)
    }

    // MARK: MeetingStore

    func test_store_createSaveLoadAndList() throws {
        let store = MeetingStore(root: tmp)
        let older = try store.create(startedAt: Date(timeIntervalSince1970: 1_000), hasSystemAudio: true)
        var newer = try store.create(startedAt: Date(timeIntervalSince1970: 2_000), hasSystemAudio: false)
        newer.state = .recorded
        newer.durationSeconds = 12
        try store.save(newer)

        XCTAssertEqual(store.all().map(\.id), [newer.id, older.id])
        XCTAssertEqual(store.load(newer.id)?.state, .recorded)
        XCTAssertEqual(store.load(older.id)?.hasSystemAudio, true)
    }

    func test_store_sameSecond_getsUniqueFolders() throws {
        let store = MeetingStore(root: tmp)
        let date = Date(timeIntervalSince1970: 5_000)
        let a = try store.create(startedAt: date, hasSystemAudio: false)
        let b = try store.create(startedAt: date, hasSystemAudio: false)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_store_recoversMeetingsLeftInRecordingState() throws {
        let store = MeetingStore(root: tmp)
        let meeting = try store.create(startedAt: Date(), hasSystemAudio: false)
        let writer = SegmentedAudioWriter(directory: store.audioFolder(for: meeting.id), prefix: Meeting.micPrefix)
        writer.append(sine(seconds: 2))
        writer.finish()

        XCTAssertEqual(store.recoverInterrupted(), 1)
        let recovered = try XCTUnwrap(store.load(meeting.id))
        XCTAssertEqual(recovered.state, .interrupted)
        XCTAssertEqual(recovered.durationSeconds, 2, accuracy: 0.01)
        XCTAssertEqual(store.recoverInterrupted(), 0, "drugi raz nic do odzyskania")
    }

    func test_clockFormatting() {
        XCTAssertEqual(AppDelegate.clock(5), "0:05")
        XCTAssertEqual(AppDelegate.clock(754), "12:34")
        XCTAssertEqual(AppDelegate.clock(3_725), "1:02:05")
    }

    // MARK: Poprawki z recenzji PR #2

    func test_resampler_downmixesRightOnlyChannel() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 9_600)!
        buf.frameLength = 9_600
        for i in 0..<9_600 {
            buf.floatChannelData![0][i] = 0                                              // lewy: cisza
            buf.floatChannelData![1][i] = 0.4 * sin(2 * .pi * 440 * Float(i) / 48_000)   // prawy: rozmówca
        }
        let out = MonoResampler().convert(buf)
        XCTAssertTrue(out.contains { abs($0) > 0.05 }, "dźwięk tylko z prawego kanału nie może zniknąć")
    }

    func test_alignmentPadding() {
        XCTAssertEqual(MeetingRecorder.alignmentPadding(reference: 160_000, track: 0), 160_000)
        XCTAssertEqual(MeetingRecorder.alignmentPadding(reference: 1_000, track: 4_000), 0)
    }

    func test_store_recoversStuckProcessingStates() throws {
        let store = MeetingStore(root: tmp)
        var a = try store.create(startedAt: Date(timeIntervalSince1970: 1_000), hasSystemAudio: false)
        a.state = .transcribing
        try store.save(a)
        var b = try store.create(startedAt: Date(timeIntervalSince1970: 2_000), hasSystemAudio: false)
        b.state = .summarizing
        try store.save(b)
        try "t".write(to: store.transcriptURL(for: b.id), atomically: true, encoding: .utf8)

        store.recoverInterrupted()
        XCTAssertEqual(store.load(a.id)?.state, .recorded, "brak transkryptu → wróć do „nagrane”")
        XCTAssertEqual(store.load(b.id)?.state, .transcribed, "jest transkrypt, brak podsumowania → „przepisane”")
    }

    func test_detector_webkitShownAsSafari() {
        XCTAssertEqual(MeetingDetector.displayAliases["com.apple.WebKit"], "com.apple.Safari")
    }
}
