import XCTest
@testable import Dyktando

final class HotkeyMonitorTests: XCTestCase {
    @MainActor
    func test_pushToTalk_emitsStartAndStop() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }

        monitor.simulatePushToTalkDown()
        monitor.simulatePushToTalkUp()

        XCTAssertEqual(events, [.startCapture(.singleEngine), .stopCapture])
    }

    @MainActor
    func test_toggle_emitsStartThenStop() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }

        monitor.simulateToggleTap()
        XCTAssertEqual(events, [.startCapture(.singleEngine)])

        monitor.simulateToggleTap()
        XCTAssertEqual(events, [.startCapture(.singleEngine), .stopCapture])
    }

    @MainActor
    func test_comparisonMode_pushAndRelease() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }
        monitor.simulateComparisonModeDown()
        monitor.simulateComparisonModeUp()
        XCTAssertEqual(events, [.startCapture(.comparison), .stopCapture])
    }

    @MainActor
    func test_switchModelAndOpenSettings_areOneShotEvents() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }
        monitor.simulateSwitchModelTap()
        monitor.simulateOpenSettingsTap()
        XCTAssertEqual(events, [.switchModel, .openSettings])
    }

    @MainActor
    func test_doubleStart_isIdempotent() {
        // If the OS sends a second key-down without an up (e.g., autorepeat), don't double-emit start.
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }
        monitor.simulatePushToTalkDown()
        monitor.simulatePushToTalkDown()
        monitor.simulatePushToTalkUp()
        XCTAssertEqual(events, [.startCapture(.singleEngine), .stopCapture])
    }
}
