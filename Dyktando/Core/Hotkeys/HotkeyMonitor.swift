import Foundation
import KeyboardShortcuts

enum HotkeyEvent: Equatable {
    case startCapture
    case stopCapture
    /// Nagranie przerwane (np. prawy ⌘ użyty jako część skrótu ⌘C) — odrzuć bez transkrypcji.
    case cancelCapture
    case openSettings
}

@MainActor
final class HotkeyMonitor {
    private let emit: (HotkeyEvent) -> Void
    private var isCapturing = false
    /// Kto zaczął bieżące nagranie — modyfikator nie może przerwać nagrania z F5/toggle.
    private enum Source { case shortcut, modifier }
    private var source: Source?
    private var modifierMonitor: ModifierKeyMonitor?

    init(emit: @escaping (HotkeyEvent) -> Void) {
        self.emit = emit
        bind()
    }

    private func bind() {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            NSLog("[Hotkey] PTT keyDown")
            self?.start()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            NSLog("[Hotkey] PTT keyUp")
            self?.stop()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.toggle()
        }
        KeyboardShortcuts.onKeyDown(for: .openSettings) { [weak self] in
            self?.emit(.openSettings)
        }
        modifierMonitor = ModifierKeyMonitor { [weak self] action in
            self?.handleModifier(action)
        }
    }

    private func handleModifier(_ action: ModifierPTTState.Action) {
        switch action {
        case .start:  start(source: .modifier)
        case .stop:   if source == .modifier { stop() }
        case .cancel: if source == .modifier { cancel() }
        }
    }

    private func cancel() {
        guard isCapturing else { return }
        isCapturing = false
        source = nil
        emit(.cancelCapture)
    }

    private func start(source: Source = .shortcut) {
        guard !isCapturing else { return }
        isCapturing = true
        self.source = source
        emit(.startCapture)
    }

    private func stop() {
        guard isCapturing else { return }
        isCapturing = false
        source = nil
        emit(.stopCapture)
    }

    private func toggle() {
        isCapturing ? stop() : start()
    }

    // MARK: - Testing seams
    #if DEBUG
    func simulatePushToTalkDown() { start() }
    func simulatePushToTalkUp() { stop() }
    func simulateToggleTap() { toggle() }
    func simulateOpenSettingsTap() { emit(.openSettings) }
    func simulateCancel() { cancel() }
    func simulateModifier(_ action: ModifierPTTState.Action) { handleModifier(action) }
    #endif
}
