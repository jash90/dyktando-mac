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

        case .openTarget(let target):
            await MainActor.run { Self.open(target) }

        case .wait(let ms):
            try? await Task.sleep(for: .milliseconds(ms))
        }
    }

    // MARK: - Keys

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
