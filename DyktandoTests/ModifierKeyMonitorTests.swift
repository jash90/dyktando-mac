import AppKit
import XCTest
@testable import Dyktando

final class ModifierKeyMonitorTests: XCTestCase {
    private let rightCmd = ModifierKey.rightCommand
    private let cmdFlag: UInt = 0x100000   // NSEvent.ModifierFlags.command
    private let rightCmdDown: UInt = 0x100000 | 0x10
    private let leftCmdDown: UInt = 0x100000 | 0x08

    func test_holdAndRelease_startsAndStops() {
        var s = ModifierPTTState()
        XCTAssertEqual(s.flagsChanged(keyCode: 54, flags: rightCmdDown, target: rightCmd), .start)
        XCTAssertEqual(s.flagsChanged(keyCode: 54, flags: 0, target: rightCmd), .stop)
    }

    func test_leftCommand_isIgnored() {
        var s = ModifierPTTState()
        XCTAssertNil(s.flagsChanged(keyCode: 55, flags: leftCmdDown, target: rightCmd))
        XCTAssertNil(s.flagsChanged(keyCode: 55, flags: 0, target: rightCmd))
    }

    func test_shortcutWhileHeld_cancelsWithoutStop() {
        var s = ModifierPTTState()
        XCTAssertEqual(s.flagsChanged(keyCode: 54, flags: rightCmdDown, target: rightCmd), .start)
        XCTAssertEqual(s.otherKeyDown(), .cancel)          // ⌘C
        XCTAssertNil(s.otherKeyDown())                      // kolejne klawisze — już anulowane
        XCTAssertNil(s.flagsChanged(keyCode: 54, flags: 0, target: rightCmd))  // puszczenie: bez .stop
        // Następne przytrzymanie działa normalnie
        XCTAssertEqual(s.flagsChanged(keyCode: 54, flags: rightCmdDown, target: rightCmd), .start)
        XCTAssertEqual(s.flagsChanged(keyCode: 54, flags: 0, target: rightCmd), .stop)
    }

    func test_otherModifierWhileHeld_cancels() {
        var s = ModifierPTTState()
        _ = s.flagsChanged(keyCode: 54, flags: rightCmdDown, target: rightCmd)
        XCTAssertEqual(s.flagsChanged(keyCode: 56, flags: rightCmdDown | 0x20000, target: rightCmd), .cancel)  // + ⇧
    }

    func test_rightCommandRelease_whileLeftStillHeld_stops() {
        var s = ModifierPTTState()
        _ = s.flagsChanged(keyCode: 55, flags: leftCmdDown, target: rightCmd)
        XCTAssertEqual(s.flagsChanged(keyCode: 54, flags: leftCmdDown | 0x10, target: rightCmd), .start)
        // Prawy puszczony, lewy dalej trzymany: ogólna flaga .command nadal ustawiona, maska prawego — nie
        XCTAssertEqual(s.flagsChanged(keyCode: 54, flags: leftCmdDown, target: rightCmd), .stop)
    }

    func test_otherKeysWithoutModifier_doNothing() {
        var s = ModifierPTTState()
        XCTAssertNil(s.otherKeyDown())
    }

    func test_fnKey_usesFunctionFlag() {
        var s = ModifierPTTState()
        let fn = NSEvent.ModifierFlags.function.rawValue
        XCTAssertEqual(s.flagsChanged(keyCode: 63, flags: fn, target: .function), .start)
        XCTAssertEqual(s.flagsChanged(keyCode: 63, flags: 0, target: .function), .stop)
    }

    @MainActor
    func test_hotkeyMonitor_cancelEmitsCancelCapture() {
        var events: [HotkeyEvent] = []
        let monitor = HotkeyMonitor { events.append($0) }
        monitor.simulatePushToTalkDown()
        monitor.simulateCancel()
        monitor.simulateCancel()   // drugi raz: już nie nagrywa
        XCTAssertEqual(events, [.startCapture, .cancelCapture])
    }
}
