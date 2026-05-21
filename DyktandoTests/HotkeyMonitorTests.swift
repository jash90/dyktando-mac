import XCTest
@testable import Dyktando

final class HotkeyMonitorTests: XCTestCase {
    @MainActor
    func test_pushToTalk_emitsStartAndStop() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }

        monitor.simulatePushToTalkDown()
        monitor.simulatePushToTalkUp()

        XCTAssertEqual(events, [.startCapture, .stopCapture])
    }

    @MainActor
    func test_toggle_emitsStartThenStop() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }

        monitor.simulateToggleTap()
        XCTAssertEqual(events, [.startCapture])

        monitor.simulateToggleTap()
        XCTAssertEqual(events, [.startCapture, .stopCapture])
    }

    @MainActor
    func test_openSettings_isOneShotEvent() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }
        monitor.simulateOpenSettingsTap()
        XCTAssertEqual(events, [.openSettings])
    }

    @MainActor
    func test_doubleStart_isIdempotent() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }
        monitor.simulatePushToTalkDown()
        monitor.simulatePushToTalkDown()
        monitor.simulatePushToTalkUp()
        XCTAssertEqual(events, [.startCapture, .stopCapture])
    }
}
