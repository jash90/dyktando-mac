import XCTest
import KeyboardShortcuts
@testable import Dyktando

final class ShortcutNamesTests: XCTestCase {
    func test_allNamesAreDeclared() {
        // Just touch all of them; if any aren't declared this won't compile.
        _ = KeyboardShortcuts.Name.pushToTalk
        _ = KeyboardShortcuts.Name.toggleDictation
        _ = KeyboardShortcuts.Name.openSettings
    }

    func test_pushToTalk_hasDefaultF5() {
        let defaultShortcut = KeyboardShortcuts.Name.pushToTalk.defaultShortcut
        XCTAssertEqual(defaultShortcut?.key, .f5)
        XCTAssertEqual(defaultShortcut?.modifiers, [])
    }

    func test_toggleDictation_hasDefaultCtrlOptSpace() {
        let defaultShortcut = KeyboardShortcuts.Name.toggleDictation.defaultShortcut
        XCTAssertEqual(defaultShortcut?.key, .space)
        XCTAssertTrue(defaultShortcut?.modifiers.contains(.control) == true)
        XCTAssertTrue(defaultShortcut?.modifiers.contains(.option) == true)
    }
}
