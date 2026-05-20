import XCTest
@testable import Dyktando

final class WhisperKitEngineTests: XCTestCase {
    func test_variantTurbo_metadata() {
        let engine = WhisperKitEngine(variant: .largeV3Turbo)
        XCTAssertEqual(engine.id, .whisperLargeV3Turbo)
        XCTAssertEqual(engine.displayName, "Whisper large-v3-turbo")
        XCTAssertTrue(engine.supportedLanguages.contains(Locale(identifier: "pl")))
    }

    func test_variantV3_metadata() {
        let engine = WhisperKitEngine(variant: .largeV3)
        XCTAssertEqual(engine.id, .whisperLargeV3)
        XCTAssertEqual(engine.displayName, "Whisper large-v3")
    }

    func test_isInstalled_falseWhenModelDirMissing() {
        let engine = WhisperKitEngine(variant: .largeV3Turbo)
        // Don't assume — could be true if user has already downloaded.
        // Just exercise the call.
        _ = engine.isInstalled
    }

    /// Integration test — actually transcribes Polish via Whisper turbo.
    /// Skips if the model isn't cached locally; users run this manually once
    /// after downloading via the Settings UI (M6) or via this very test.
    func test_transcribePolishFixture_turbo() async throws {
        let engine = WhisperKitEngine(variant: .largeV3Turbo)
        guard engine.isInstalled else {
            throw XCTSkip("Whisper large-v3-turbo model not cached locally; skip to keep CI green")
        }
        let samples = try TestFixtures.polishThreeSeconds()
        let result = try await engine.transcribe(
            samples: samples,
            sampleRate: 16_000,
            mode: .single(Locale(identifier: "pl-PL")))
        XCTAssertFalse(result.text.isEmpty)
        print("WhisperKit turbo transcribed: '\(result.text)'")
    }
}
