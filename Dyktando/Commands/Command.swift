import AppKit
import Foundation

/// A voice command: one trigger phrase, an ordered list of actions to run
/// when the post-processed transcription matches the trigger exactly.
struct Command: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var trigger: String
    var actions: [CommandAction]
    var enabled: Bool

    init(id: UUID = UUID(),
         name: String = "",
         trigger: String = "",
         actions: [CommandAction] = [],
         enabled: Bool = true) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.actions = actions
        self.enabled = enabled
    }
}

enum CommandAction: Codable, Equatable, Identifiable {
    case pressKeys(KeyCombo)
    case typeText(String)
    case openTarget(OpenTarget)
    case wait(milliseconds: Int)

    /// Stable per-action id so SwiftUI lists can track moves and edits.
    var id: UUID { storageID }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind, uuid, keyCombo, target, milliseconds, text
    }
    private enum Kind: String, Codable { case pressKeys, typeText, openTarget, wait }

    private var storageID: UUID {
        switch self {
        case .pressKeys(let k):  return k.uuid
        case .openTarget(let t): return t.uuid
        case .typeText(_):       return _staticID(for: "type")
        case .wait(_):           return _staticID(for: "wait")
        }
    }
    private func _staticID(for tag: String) -> UUID {
        // Stable per-kind UUID — multiple actions of the same kind end up
        // sharing an id; SwiftUI's enumerated() workaround in CommandsView
        // handles that.
        UUID(uuidString: "00000000-0000-0000-0000-\(tag.padding(toLength: 12, withPad: "0", startingAt: 0))") ?? UUID()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pressKeys(let k):
            try c.encode(Kind.pressKeys, forKey: .kind)
            try c.encode(k, forKey: .keyCombo)
        case .typeText(let s):
            try c.encode(Kind.typeText, forKey: .kind)
            try c.encode(s, forKey: .text)
        case .openTarget(let t):
            try c.encode(Kind.openTarget, forKey: .kind)
            try c.encode(t, forKey: .target)
        case .wait(let ms):
            try c.encode(Kind.wait, forKey: .kind)
            try c.encode(ms, forKey: .milliseconds)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .pressKeys:
            self = .pressKeys(try c.decode(KeyCombo.self, forKey: .keyCombo))
        case .typeText:
            self = .typeText(try c.decode(String.self, forKey: .text))
        case .openTarget:
            self = .openTarget(try c.decode(OpenTarget.self, forKey: .target))
        case .wait:
            self = .wait(milliseconds: try c.decode(Int.self, forKey: .milliseconds))
        }
    }
}

/// A keyboard shortcut to synthesize via CGEvent.
struct KeyCombo: Codable, Equatable {
    /// Stable identity for SwiftUI list bindings.
    var uuid: UUID
    /// Virtual keycode (Carbon HIToolbox numbering — same as NSEvent.keyCode).
    var keyCode: UInt16
    /// Bitmask of NSEvent.ModifierFlags raw values for the canonical four
    /// modifiers: command, option, control, shift. Encoded as the raw value
    /// directly so this also lines up with CGEventFlags bit positions.
    var modifiersRaw: UInt
    /// Human-readable label captured at record time (e.g. "⌘⌥V").
    var label: String

    init(uuid: UUID = UUID(),
         keyCode: UInt16,
         modifiersRaw: UInt,
         label: String) {
        self.uuid = uuid
        self.keyCode = keyCode
        self.modifiersRaw = modifiersRaw
        self.label = label
    }

    var nsModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRaw)
    }

    var cgFlags: CGEventFlags {
        var flags = CGEventFlags()
        if nsModifiers.contains(.command)  { flags.insert(.maskCommand)   }
        if nsModifiers.contains(.option)   { flags.insert(.maskAlternate) }
        if nsModifiers.contains(.control)  { flags.insert(.maskControl)   }
        if nsModifiers.contains(.shift)    { flags.insert(.maskShift)     }
        return flags
    }
}

/// What to open when running an `.openTarget` action.
enum OpenTarget: Codable, Equatable {
    /// A bundle identifier like `com.apple.mail`.
    case bundleID(String, uuid: UUID = UUID())
    /// A file:// URL or an absolute path to an .app.
    case fileURL(URL, uuid: UUID = UUID())
    /// An http(s)://, mailto:, x-apple-...://, etc.
    case url(URL, uuid: UUID = UUID())

    var uuid: UUID {
        switch self {
        case .bundleID(_, let u), .fileURL(_, let u), .url(_, let u): return u
        }
    }

    var displayString: String {
        switch self {
        case .bundleID(let id, _): return id
        case .fileURL(let url, _): return url.path
        case .url(let url, _):     return url.absoluteString
        }
    }
}
