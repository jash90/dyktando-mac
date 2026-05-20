import XCTest
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
}
