import XCTest
@testable import Dyktando

final class FocusClassifierTests: XCTestCase {
    private func kind(_ s: FocusSnapshot) -> FocusKind { FocusClassifier.classify(s) }

    func test_textFields_areEditable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertEqual(kind(FocusSnapshot(role: role)), .editable, role)
        }
    }

    func test_iTerm_textArea_isEditable() {  // zmierzone: iTerm2 → AXTextArea, value settable
        XCTAssertEqual(kind(FocusSnapshot(role: "AXTextArea", valueSettable: true, hasSelectedTextRange: true,
                                          bundleID: "com.googlecode.iterm2")), .editable)
    }

    func test_browserContentEditable_isEditable() {
        XCTAssertEqual(kind(FocusSnapshot(role: "AXGroup", hasEditableAncestor: true)), .editable)
    }

    func test_buttonsAndLists_areNotEditable() {
        XCTAssertEqual(kind(FocusSnapshot(role: "AXButton")), .notEditable)
        XCTAssertEqual(kind(FocusSnapshot(role: "AXOutline")), .notEditable)
        XCTAssertEqual(kind(FocusSnapshot(role: "AXWindow", subrole: "AXDialog")), .notEditable)
    }

    func test_finderGroup_isNotEditable() {  // zmierzone: Finder → AXGroup
        XCTAssertEqual(kind(FocusSnapshot(role: "AXGroup", hasSelectedTextRange: true, bundleID: "com.apple.finder")),
                       .notEditable)
    }

    func test_noFocusedElement_isNotEditable() {  // kAXErrorNoValue
        XCTAssertEqual(kind(FocusSnapshot(axError: -25212)), .notEditable)
    }

    func test_appThatCannotAnswer_isUnknown_soWeStillPaste() {  // zmierzone: Word → -25204
        XCTAssertEqual(kind(FocusSnapshot(bundleID: "com.microsoft.Word", axError: -25204)), .unknown)
        XCTAssertEqual(kind(FocusSnapshot(role: "AXGroup")), .unknown)
        XCTAssertEqual(kind(FocusSnapshot(role: "AXWebArea")), .unknown)
    }

    func test_pasteDecision() {
        XCTAssertEqual(PasteDecision.decide(accessibilityTrusted: true, focus: .editable), .paste)
        XCTAssertEqual(PasteDecision.decide(accessibilityTrusted: true, focus: .unknown), .paste)
        XCTAssertEqual(PasteDecision.decide(accessibilityTrusted: true, focus: .notEditable), .clipboardNoTextField)
        XCTAssertEqual(PasteDecision.decide(accessibilityTrusted: false, focus: .editable), .clipboardNoPermission)
    }
}
