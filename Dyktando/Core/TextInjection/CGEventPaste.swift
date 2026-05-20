import CoreGraphics

enum CGEventPaste {
    /// ANSI virtual keycode for 'V' on macOS.
    private static let virtualKeyV: CGKeyCode = 9

    /// Returns [keyDown ⌘V, keyUp ⌘V]. Exposed for testing.
    static func makeEvents() -> [CGEvent] {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: virtualKeyV,
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: virtualKeyV,
                               keyDown: false) else {
            return []
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        return [down, up]
    }

    /// Posts the ⌘V sequence to the foreground app. Requires Accessibility permission
    /// — without it, the events are silently dropped by the system.
    static func dispatch() {
        for event in makeEvents() {
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
