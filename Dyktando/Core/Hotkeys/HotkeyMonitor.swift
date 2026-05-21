import Foundation
import KeyboardShortcuts

enum HotkeyEvent: Equatable {
    case startCapture
    case stopCapture
    case openSettings
}

@MainActor
final class HotkeyMonitor {
    private let emit: (HotkeyEvent) -> Void
    private var isCapturing = false

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
    }

    private func start() {
        guard !isCapturing else { return }
        isCapturing = true
        emit(.startCapture)
    }

    private func stop() {
        guard isCapturing else { return }
        isCapturing = false
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
    #endif
}
