import XCTest
@testable import Dyktando

final class AppleSpeechEngineTests: XCTestCase {
    func test_displayName_and_id() {
        let engine = AppleSpeechEngine()
        XCTAssertEqual(engine.id, .appleSpeechPL)
        XCTAssertEqual(engine.displayName, "Apple Speech (pl-PL)")
    }

    func test_supportedLanguages_includesPL() {
        let engine = AppleSpeechEngine()
        XCTAssertTrue(engine.supportedLanguages.contains(Locale(identifier: "pl-PL")))
    }

    func test_transcribePolishFixture() async throws {
        // SFSpeechRecognizer needs authorization. In test contexts the system may
        // already have authorized, may pop a one-time prompt, or may run in a
        // restricted CI env that denies. If denied, skip with a clear message.
        let engine = AppleSpeechEngine()

        let samples = try TestFixtures.polishThreeSeconds()
        do {
            let result = try await engine.transcribe(
                samples: samples,
                sampleRate: 16_000,
                mode: .single(Locale(identifier: "pl-PL")))

            XCTAssertFalse(result.text.isEmpty,
                           "Expected non-empty transcription from synthetic Polish fixture; got empty")
            XCTAssertGreaterThan(result.inferenceMillis, 0)
            // Don't assert exact text — SFSpeechRecognizer accuracy on synthetic TTS
            // varies. Just confirm we got SOMETHING back.
            print("AppleSpeech transcribed: '\(result.text)'")
        } catch EngineError.notAuthorized {
            throw XCTSkip("SFSpeechRecognizer not authorized in this environment")
        } catch EngineError.notInstalled {
            throw XCTSkip("Polish on-device speech model not available in this environment")
        }
    }
}
