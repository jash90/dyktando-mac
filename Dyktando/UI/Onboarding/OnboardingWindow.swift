import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init(state: OnboardingState, onFinish: @escaping () -> Void) {
        let root = OnboardingRoot(state: state, onFinish: onFinish)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Witamy w Dyktando"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: root)
        self.init(window: window)
    }
}

struct OnboardingRoot: View {
    @ObservedObject var state: OnboardingState
    let onFinish: () -> Void

    var body: some View {
        VStack {
            ProgressView(value: Double(state.step.rawValue),
                         total: Double(OnboardingStep.allCases.count - 1))
                .padding(.bottom, 8)

            switch state.step {
            case .welcome:       WelcomeStep { state.next() }
            case .microphone:    MicrophoneStep(permissions: state.permissions) { state.next() }
            case .accessibility: AccessibilityStep(permissions: state.permissions) { state.next() }
            case .pickModel:     PickModelStep { state.next() }
            case .testShortcut:  TestShortcutStep { state.next() }
            case .done:          DoneStep(finish: onFinish)
            }
        }
        .frame(width: 480, height: 320)
        .padding(24)
    }
}
