import XCTest
import CoreGraphics
@testable import Dyktando

final class CGEventPasteTests: XCTestCase {
    func test_makeEvents_returnsTwoEvents() {
        XCTAssertEqual(CGEventPaste.makeEvents().count, 2)
    }

    func test_makeEvents_useVirtualKeyV() {
        for event in CGEventPaste.makeEvents() {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 9)
        }
    }

    func test_makeEvents_keyDownThenKeyUp() {
        let events = CGEventPaste.makeEvents()
        XCTAssertEqual(events[0].type, .keyDown)
        XCTAssertEqual(events[1].type, .keyUp)
    }

    func test_makeEvents_haveCommandModifier() {
        for event in CGEventPaste.makeEvents() {
            XCTAssertTrue(event.flags.contains(.maskCommand))
        }
    }
}
