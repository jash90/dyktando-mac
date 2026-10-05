import AppKit

/// Klawisz modyfikujący używany samodzielnie jako push-to-talk (np. prawy ⌘).
/// KeyboardShortcuts nie obsługuje skrótów bez zwykłego klawisza, więc te obsługujemy osobno.
enum ModifierKey: String, CaseIterable, Identifiable, Sendable {
    case rightCommand, rightOption, rightShift, rightControl, function

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rightCommand: return "Prawy ⌘ Command"
        case .rightOption:  return "Prawy ⌥ Option"
        case .rightShift:   return "Prawy ⇧ Shift"
        case .rightControl: return "Prawy ⌃ Control"
        case .function:     return "fn / 🌐"
        }
    }

    /// Kod klawisza z `NSEvent.keyCode` dla zdarzenia `.flagsChanged`.
    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightOption:  return 61
        case .rightShift:   return 60
        case .rightControl: return 62
        case .function:     return 63
        }
    }

    /// Maska „device-dependent” (NX_DEVICER*KEYMASK) — odróżnia prawy klawisz od lewego.
    var deviceMask: UInt {
        switch self {
        case .rightCommand: return 0x0010
        case .rightOption:  return 0x0040
        case .rightShift:   return 0x0004
        case .rightControl: return 0x2000
        case .function:     return NSEvent.ModifierFlags.function.rawValue
        }
    }

    static let defaultsKey = "modifierPushToTalk"

    /// Bieżący wybór z Ustawień (`nil` = wyłączone).
    static var current: ModifierKey? {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(ModifierKey.init(rawValue:))
    }
}

/// Maszyna stanów push-to-talk na samym modyfikatorze. Czysta logika — testowana bez NSEvent.
struct ModifierPTTState {
    enum Action: Equatable { case start, stop, cancel }

    private(set) var isHeld = false
    private(set) var cancelled = false

    /// Zdarzenie `.flagsChanged`.
    mutating func flagsChanged(keyCode: UInt16, flags: UInt, target: ModifierKey) -> Action? {
        guard keyCode == target.keyCode else {
            // Inny modyfikator wciśnięty w trakcie (np. prawy ⌘ + ⇧) — to skrót, nie dyktowanie.
            return isHeld ? cancel() : nil
        }
        let down = flags & target.deviceMask != 0
        if down, !isHeld {
            isHeld = true
            cancelled = false
            return .start
        }
        if !down, isHeld {
            isHeld = false
            return cancelled ? nil : .stop
        }
        return nil
    }

    /// Zwykły klawisz wciśnięty, gdy modyfikator jest trzymany (np. ⌘C) — anuluj nagranie.
    mutating func otherKeyDown() -> Action? {
        isHeld ? cancel() : nil
    }

    private mutating func cancel() -> Action? {
        guard !cancelled else { return nil }
        cancelled = true
        return .cancel
    }
}

/// Globalny + lokalny nasłuch `.flagsChanged` / `.keyDown` (wymaga uprawnienia Dostępności,
/// o które aplikacja i tak prosi do wklejania tekstu).
@MainActor
final class ModifierKeyMonitor {
    private var state = ModifierPTTState()
    private var monitors: [Any] = []
    private let onAction: (ModifierPTTState.Action) -> Void

    init(onAction: @escaping (ModifierPTTState.Action) -> Void) {
        self.onAction = onAction
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        guard let target = ModifierKey.current else { return }
        let action: ModifierPTTState.Action?
        if event.type == .flagsChanged {
            action = state.flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags.rawValue, target: target)
        } else {
            action = state.otherKeyDown()
        }
        if let action {
            NSLog("[Hotkey] modifier %@ → %@", target.rawValue, String(describing: action))
            onAction(action)
        }
    }

    func invalidate() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
