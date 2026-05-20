import XCTest
@testable import Dyktando

@MainActor
final class PermissionsServiceTests: XCTestCase {
    func test_initializesWithCurrentStatus() {
        let service = PermissionsService()
        // Just touch the published properties; don't assert specific values because
        // they depend on real user permissions.
        _ = service.microphone
        _ = service.accessibility
        // Both should be readable without crashing.
    }

    func test_refreshAccessibility_isIdempotent() {
        let service = PermissionsService()
        let before = service.accessibility
        service.refreshAccessibility()
        XCTAssertEqual(service.accessibility, before, "Refresh should not change state in test context")
    }
}
