import XCTest
@testable import Dyktando

@MainActor
final class EngineRegistryTests: XCTestCase {
    func test_registry_containsBothEngines() {
        let registry = EngineRegistry()
        XCTAssertNotNil(registry.engine(for: .appleSpeechPL))
        XCTAssertNotNil(registry.engine(for: .parakeetTDTv3))
    }

    func test_active_returnsParakeetWhenInstalled() {
        let registry = EngineRegistry()
        let prefs = Preferences.shared
        prefs.defaultEngineID = EngineID.parakeetTDTv3.rawValue
        defer { prefs.defaultEngineID = EngineID.parakeetTDTv3.rawValue }

        let active = registry.active(prefs: prefs)

        // Parakeet may not be downloaded in CI; either it's active, or we
        // fall back to Apple Speech.
        if registry.engine(for: .parakeetTDTv3)?.isInstalled == true {
            XCTAssertEqual(active.id, .parakeetTDTv3)
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
