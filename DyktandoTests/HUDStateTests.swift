import XCTest
@testable import Dyktando

@MainActor
final class HUDStateTests: XCTestCase {
    func test_initial_isIdle() {
        let state = HUDState()
        XCTAssertEqual(state.phase, .idle)
    }

    func test_beginListening_setsListening() {
        let state = HUDState()
        state.beginListening()
        XCTAssertEqual(state.phase, .listening)
    }

    func test_beginTranscribing_setsTranscribing() {
        let state = HUDState()
        state.beginListening()
        state.beginTranscribing()
        XCTAssertEqual(state.phase, .transcribing)
    }

    func test_finish_setsPreview() {
        let state = HUDState()
        state.beginListening()
        state.beginTranscribing()
        state.finish(preview: "hello")
        XCTAssertEqual(state.phase, .preview("hello"))
    }

    func test_level_updates() {
        let state = HUDState()
        state.level = 0.42
        XCTAssertEqual(state.level, 0.42)
    }
}
