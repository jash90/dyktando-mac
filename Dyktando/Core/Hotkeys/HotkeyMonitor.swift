import Foundation
import KeyboardShortcuts

enum CaptureKind: Equatable {
    case singleEngine
    case comparison
}

enum HotkeyEvent: Equatable {
    case startCapture(CaptureKind)
    case stopCapture
    case switchModel
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
            self?.start(.singleEngine)
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            NSLog("[Hotkey] PTT keyUp")
            self?.stop()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.toggle(.singleEngine)
        }
        KeyboardShortcuts.onKeyDown(for: .comparisonMode) { [weak self] in
            self?.start(.comparison)
        }
        KeyboardShortcuts.onKeyUp(for: .comparisonMode) { [weak self] in
            self?.stop()
        }
        KeyboardShortcuts.onKeyDown(for: .switchModel) { [weak self] in
            self?.emit(.switchModel)
        }
        KeyboardShortcuts.onKeyDown(for: .openSettings) { [weak self] in
            self?.emit(.openSettings)
        }
    }

    private func start(_ kind: CaptureKind) {
        guard !isCapturing else { return }
        isCapturing = true
        emit(.startCapture(kind))
    }

    private func stop() {
        guard isCapturing else { return }
        isCapturing = false
        emit(.stopCapture)
    }

    private func toggle(_ kind: CaptureKind) {
        isCapturing ? stop() : start(kind)
    }

    // MARK: - Testing seams
    #if DEBUG
    func simulatePushToTalkDown() { start(.singleEngine) }
    func simulatePushToTalkUp() { stop() }
    func simulateToggleTap() { toggle(.singleEngine) }
    func simulateComparisonModeDown() { start(.comparison) }
    func simulateComparisonModeUp() { stop() }
    func simulateSwitchModelTap() { emit(.switchModel) }
    func simulateOpenSettingsTap() { emit(.openSettings) }
    #endif
}
