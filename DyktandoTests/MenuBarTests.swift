import XCTest
@testable import Dyktando

final class MenuBarTests: XCTestCase {
    @MainActor
    func test_menuBarController_holdsStatusItem() {
        let controller = MenuBarController()
        XCTAssertEqual(controller.statusItem.button?.image?.isTemplate, true)
    }

    @MainActor
    func test_menuBarController_menuHasQuitAndSettings() {
        let controller = MenuBarController()
        let titles = (controller.statusItem.menu?.items ?? []).map(\.title)
        XCTAssertTrue(titles.contains("Ustawienia…"))
        XCTAssertTrue(titles.contains("Zakończ"))
    }
}
