import AppKit
import SwiftUI

/// Captures the next ⌘/⌥/⌃/⇧ + key press inside a local NSEvent monitor and
/// returns the resulting `KeyCombo` to the binding. Escape cancels.
struct KeyComboRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: recording ? "record.circle.fill" : "keyboard")
                    .foregroundStyle(recording ? .red : .secondary)
                Text(label)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(minWidth: 140)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(recording ? 0.6 : 0.3), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private var label: String {
        if recording { return "Wciśnij kombinację (Esc = anuluj)" }
        return combo?.label ?? "Wybierz klawisze"
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        guard !recording else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape (keyCode 53) cancels without changing the combo.
            if event.keyCode == 53 {
                stop()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Require at least one modifier — sending a bare keystroke from
            // a command is almost never what the user means and easy to mis-fire.
            guard !mods.isEmpty else { return nil }

            let label = Self.format(event: event, modifiers: mods)
            combo = KeyCombo(keyCode: event.keyCode,
                             modifiersRaw: mods.rawValue,
                             label: label)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    // MARK: - Display

    private static func format(event: NSEvent, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control)  { s += "⌃" }
        if modifiers.contains(.option)   { s += "⌥" }
        if modifiers.contains(.shift)    { s += "⇧" }
        if modifiers.contains(.command)  { s += "⌘" }
        s += keyName(for: event)
        return s
    }

    private static func keyName(for event: NSEvent) -> String {
        // Prefer the unmodified character (so ⌥e shows as "E", not "´").
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let ch = chars.uppercased()
            if let scalar = ch.unicodeScalars.first, scalar.isASCII {
                return ch
            }
        }
        // Fall back to a small lookup for keys without printable representation.
        return specialKeyName[event.keyCode] ?? "key\(event.keyCode)"
    }

    private static let specialKeyName: [UInt16: String] = [
        36:  "↩",  // return
        48:  "⇥",  // tab
        49:  "Space",
        51:  "⌫",  // delete
        53:  "Esc",
        76:  "⌅",  // enter
        117: "⌦",  // forward delete
        122: "F1",  120: "F2",  99:  "F3",  118: "F4",
        96:  "F5",  97:  "F6",  98:  "F7",  100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
