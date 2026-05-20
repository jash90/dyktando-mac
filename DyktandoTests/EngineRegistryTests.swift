import XCTest
@testable import Dyktando

@MainActor
final class EngineRegistryTests: XCTestCase {
    func test_registry_containsAppleAndWhisperEngines() {
        let registry = EngineRegistry()
        XCTAssertNotNil(registry.engine(for: .appleSpeechPL))
        XCTAssertNotNil(registry.engine(for: .whisperLargeV3Turbo))
        XCTAssertNotNil(registry.engine(for: .whisperLargeV3))
        // Parakeet added later
        XCTAssertNil(registry.engine(for: .parakeetTDTv3))
    }

    func test_active_fallsBackToAppleWhenWhisperNotInstalled() {
        let registry = EngineRegistry()
        let prefs = Preferences.shared
        prefs.defaultEngineID = EngineID.whisperLargeV3Turbo.rawValue
        defer { prefs.defaultEngineID = EngineID.appleSpeechPL.rawValue }

        let active = registry.active(prefs: prefs)

        // Whisper isn't downloaded in CI / fresh install → fall back to Apple.
        // If a developer has whisper cached locally, the test asserts on that path instead.
        if registry.engine(for: .whisperLargeV3Turbo)?.isInstalled == true {
            XCTAssertEqual(active.id, .whisperLargeV3Turbo)
        } else {
            XCTAssertEqual(active.id, .appleSpeechPL)
        }
    }

    func test_active_returnsAppleWhenPrefIsApple() {
        let registry = EngineRegistry()
        let prefs = Preferences.shared
        prefs.defaultEngineID = EngineID.appleSpeechPL.rawValue
        XCTAssertEqual(registry.active(prefs: prefs).id, .appleSpeechPL)
    }
}
