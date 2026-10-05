import AppKit
import ApplicationServices

/// Co ma fokus w aplikacji na pierwszym planie — decyduje, czy wklejać ⌘V automatycznie.
enum FocusKind: Equatable {
    /// Pole tekstowe / edytor — wklejamy.
    case editable
    /// Na pewno nie pole tekstowe (przycisk, lista plików, brak fokusu) — tylko schowek.
    case notEditable
    /// Aplikacja nie mówi, co ma fokus (część terminali, Word, Electron bez AX) — wklejamy jak dawniej.
    case unknown
}

/// Opis elementu z fokusem w postaci, którą da się testować bez Accessibility API.
struct FocusSnapshot: Equatable {
    var role: String?
    var subrole: String?
    var valueSettable = false
    var hasSelectedTextRange = false
    var hasEditableAncestor = false
    var bundleID: String?
    /// Kod błędu AX przy pytaniu o fokus (`nil` = odpowiedź przyszła).
    var axError: Int32?
}

enum FocusClassifier {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static let nonTextRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXList", "AXOutline", "AXTable", "AXRow",
        "AXCell", "AXImage", "AXMenuItem", "AXMenuButton", "AXMenuBar", "AXLink", "AXStaticText",
        "AXTabGroup", "AXSlider", "AXPopUpButton", "AXWindow", "AXBrowser", "AXToolbar",
        "AXDisclosureTriangle", "AXIncrementor", "AXColorWell", "AXSheet", "AXDrawer",
    ]
    /// kAXErrorNoValue: aplikacja odpowiedziała, że nic nie ma fokusu.
    static let axErrorNoValue: Int32 = -25212

    static func classify(_ s: FocusSnapshot) -> FocusKind {
        if let error = s.axError {
            return error == axErrorNoValue ? .notEditable : .unknown
        }
        if let role = s.role, textRoles.contains(role) { return .editable }
        if s.hasEditableAncestor { return .editable }                     // contenteditable w przeglądarce / Electronie
        if s.valueSettable && s.hasSelectedTextRange { return .editable }  // własne edytory tekstu
        if let role = s.role, nonTextRoles.contains(role) { return .notEditable }
        // Finder: ⌘V z tekstem w schowku nic sensownego nie zrobi poza polami nazw (te są AXTextField).
        if s.bundleID == "com.apple.finder" { return .notEditable }
        return .unknown  // AXGroup, AXWebArea, AXScrollArea… — zbyt ogólne, nie blokujemy wklejania
    }
}

enum FocusInspector {
    /// Pyta aplikację na pierwszym planie o element z fokusem (wymaga uprawnienia Dostępności).
    @MainActor
    static func current() -> (kind: FocusKind, snapshot: FocusSnapshot) {
        var snap = FocusSnapshot()
        guard let app = NSWorkspace.shared.frontmostApplication else {
            snap.axError = -1
            return (FocusClassifier.classify(snap), snap)
        }
        snap.bundleID = app.bundleIdentifier
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        // Electron (Slack, VS Code, Discord…) buduje drzewo dostępności dopiero na żądanie.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            snap.axError = err == .success ? -1 : err.rawValue
            return (FocusClassifier.classify(snap), snap)
        }
        let element = focused as! AXUIElement  // swiftlint:disable:this force_cast — typ sprawdzony wyżej
        AXUIElementSetMessagingTimeout(element, 0.25)

        snap.role = stringAttribute(element, kAXRoleAttribute)
        snap.subrole = stringAttribute(element, kAXSubroleAttribute)
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
            snap.valueSettable = settable.boolValue
        }
        var range: CFTypeRef?
        snap.hasSelectedTextRange =
            AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success
        var ancestor: CFTypeRef?
        snap.hasEditableAncestor =
            AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &ancestor) == .success
        return (FocusClassifier.classify(snap), snap)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

/// Czy wkleić ⌘V, czy zostawić tekst w schowku (i dlaczego).
enum PasteDecision: Equatable {
    case paste
    case clipboardNoTextField
    case clipboardNoPermission

    static func decide(accessibilityTrusted: Bool, focus: FocusKind) -> PasteDecision {
        guard accessibilityTrusted else { return .clipboardNoPermission }
        return focus == .notEditable ? .clipboardNoTextField : .paste
    }
}
