import AppKit
import Foundation

/// Runs a `Command`'s action chain sequentially on a background task.
///
/// Key presses are posted via `CGEvent.post(tap: .cgAnnotatedSessionEventTap)`
/// which requires Accessibility permission. App/URL opens go through
/// `NSWorkspace` and need no special permission.
struct CommandRunner {
    func run(_ command: Command) async {
        NSLog("[Commands] running '%@' (%d actions)", command.name, command.actions.count)
        for action in command.actions {
            await runAction(action)
        }
    }

    private func runAction(_ action: CommandAction) async {
        switch action {
        case .pressKeys(let combo):
            await MainActor.run { Self.dispatchKeyCombo(combo) }

        case .typeText(let text):
            await MainActor.run { Self.typeText(text) }

        case .openTarget(let target):
            await MainActor.run { Self.open(target) }

        case .wait(let ms):
            try? await Task.sleep(for: .milliseconds(ms))
        }
    }

    // MARK: - Keys

    /// Public entry-point so skills (e.g. ClaudeCodeSkill) can reuse the
    /// same dispatch path as user macros.
    static func dispatch(keyCombo: KeyCombo) {
        dispatchKeyCombo(keyCombo)
    }

    private static func dispatchKeyCombo(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(combo.keyCode),
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(combo.keyCode),
                               keyDown: false) else { return }
        down.flags = combo.cgFlags
        up.flags = combo.cgFlags
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Typing

    /// Synthesizes the given Unicode text as a stream of keyboard events,
    /// one character per event. Single-char `keyboardSetUnicodeString` events
    /// are far more compatible with terminals than batched multi-char events
    /// (Terminal.app drops the latter because `virtualKey == 0`).
    /// Newlines are sent as real Return (virtualKey 36) events.
    static func typeText(_ text: String) {
        NSLog("[Type] sending %d chars", text.count)
        let source = CGEventSource(stateID: .combinedSessionState)
        for char in text {
            if char == "\n" {
                postKey(virtualKey: 36, source: source)
            } else {
                postUnicodeChar(char, source: source)
            }
            // Tiny gap so the receiving app's run loop can drain between events.
            usleep(8_000) // 8 ms
        }
    }

    private static func postUnicodeChar(_ char: Character, source: CGEventSource?) {
        let utf16 = Array(String(char).utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        utf16.withUnsafeBufferPointer { ptr in
            down.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
            up.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
        }
        // .cghidEventTap simulates a hardware keyboard which Terminal.app and
        // most other apps trust unconditionally; .cgAnnotatedSessionEventTap
        // works too but is filtered in some sandboxes.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postKey(virtualKey: CGKeyCode, source: CGEventSource?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Open

    private static func open(_ target: OpenTarget) {
        switch target {
        case .bundleID(let id, _):
            // Bundle id → resolve to URL → openApplication so the new instance
            // takes focus reliably. `NSWorkspace.shared.launchApplication(...)`
            // is deprecated.
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url,
                                                   configuration: NSWorkspace.OpenConfiguration(),
                                                   completionHandler: nil)
            } else {
                NSLog("[Commands] no app for bundle id %@", id)
            }

        case .fileURL(let url, _):
            if url.pathExtension.lowercased() == "app" {
                NSWorkspace.shared.openApplication(at: url,
                                                   configuration: NSWorkspace.OpenConfiguration(),
                                                   completionHandler: nil)
            } else {
                NSWorkspace.shared.open(url)
            }

        case .url(let url, _):
            NSWorkspace.shared.open(url)
        }
    }
}
