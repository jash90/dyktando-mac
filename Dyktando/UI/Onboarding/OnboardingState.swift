import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case pickModel
    case testShortcut
    case done
}

@MainActor
final class OnboardingState: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    let permissions: PermissionsService

    init(permissions: PermissionsService) {
        self.permissions = permissions
    }

    func next() {
        if let nextStep = OnboardingStep(rawValue: step.rawValue + 1) {
            step = nextStep
        }
    }
}
