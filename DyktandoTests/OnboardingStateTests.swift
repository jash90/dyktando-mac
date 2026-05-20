import XCTest
@testable import Dyktando

@MainActor
final class OnboardingStateTests: XCTestCase {
    func test_startsAtWelcome() {
        let state = OnboardingState(permissions: PermissionsService())
        XCTAssertEqual(state.step, .welcome)
    }

    func test_next_progressesThroughAllSteps() {
        let state = OnboardingState(permissions: PermissionsService())
        let expected: [OnboardingStep] = [.microphone, .accessibility, .pickModel, .testShortcut, .done]
        for step in expected {
            state.next()
            XCTAssertEqual(state.step, step)
        }
    }

    func test_next_atDone_isNoOp() {
        let state = OnboardingState(permissions: PermissionsService())
        for _ in 0..<10 { state.next() }
        XCTAssertEqual(state.step, .done)
    }
}
