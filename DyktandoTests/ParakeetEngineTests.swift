import XCTest
import AVFoundation
@testable import Dyktando

final class ParakeetEngineTests: XCTestCase {
    func test_metadata() {
        let engine = ParakeetEngine()
        XCTAssertEqual(engine.id, .parakeetTDTv3)
        XCTAssertEqual(engine.displayName, "Parakeet TDT v3")
        XCTAssertTrue(engine.supportedLanguages.contains(Locale(identifier: "pl")))
        XCTAssertTrue(engine.supportedLanguages.contains(Locale(identifier: "en")))
        XCTAssertEqual(engine.supportedLanguages.count, 24)
    }

    @MainActor
    func test_registry_includesParakeet() {
        let registry = EngineRegistry()
        XCTAssertNotNil(registry.engine(for: .parakeetTDTv3))
    }

    /// Integration — skips if Parakeet model not yet cached locally.
    func test_transcribePolishFixture() async throws {
        let engine = ParakeetEngine()
        guard engine.isInstalled else {
            throw XCTSkip("Parakeet TDT v3 model not cached locally; skip to keep CI green")
        }
        let samples = try TestFixtures.polishThreeSeconds()
        let result = try await engine.transcribe(
            samples: samples,
            sampleRate: 16_000,
            mode: .single(Locale(identifier: "pl-PL")))
        XCTAssertFalse(result.text.isEmpty)
        print("Parakeet transcribed: '\(result.text)'")
    }

    /// Diagnostyka: ostatnie nagranie z aplikacji (AppPaths.support/last-recording.caf) przez świeży
    /// silnik — mierzy ładowanie modelu + pierwszą transkrypcję oraz drugą („ciepłą”).
    /// Opt-in: TEST_RUNNER_DYKTANDO_LAST_RECORDING=1
    func test_lastRecording_timing() async throws {
        guard ProcessInfo.processInfo.environment["DYKTANDO_LAST_RECORDING"] == "1" else {
            throw XCTSkip("ustaw TEST_RUNNER_DYKTANDO_LAST_RECORDING=1")
        }
        let url = AppPaths.support.appendingPathComponent("last-recording.caf")
        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let samples = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
        let engine = ParakeetEngine()
        guard engine.isInstalled else { throw XCTSkip("Parakeet nie jest zainstalowany") }
        let mode = LanguageMode.mixed(primary: Locale(identifier: "pl-PL"), allowed: [Locale(identifier: "pl-PL"), Locale(identifier: "en-US")])

        var start = Date()
        let cold = try await engine.transcribe(samples: samples, sampleRate: file.processingFormat.sampleRate, mode: mode)
        let coldSeconds = Date().timeIntervalSince(start)
        start = Date()
        let warm = try await engine.transcribe(samples: samples, sampleRate: file.processingFormat.sampleRate, mode: mode)
        let warmSeconds = Date().timeIntervalSince(start)
        print(String(format: "[last-recording] %.1f s audio | zimny (ładowanie+transkrypcja): %.1f s | ciepły: %.2f s | '%@' / '%@'",
                     Double(samples.count) / file.processingFormat.sampleRate, coldSeconds, warmSeconds, cold.text, warm.text))
    }
}
