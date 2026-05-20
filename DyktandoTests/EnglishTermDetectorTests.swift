import XCTest
@testable import Dyktando

final class EnglishTermDetectorTests: XCTestCase {
    func test_recognizesCommonTechTerms() {
        let d = EnglishTermDetector.shared
        XCTAssertTrue(d.isEnglishTerm("deployment"))
        XCTAssertTrue(d.isEnglishTerm("Deployment"))      // case-insensitive
        XCTAssertTrue(d.isEnglishTerm("DEPLOYMENT"))
        XCTAssertTrue(d.isEnglishTerm("deploy"))
        XCTAssertTrue(d.isEnglishTerm("git"))
        XCTAssertTrue(d.isEnglishTerm("commit"))
        XCTAssertTrue(d.isEnglishTerm("pull"))
        XCTAssertTrue(d.isEnglishTerm("request"))
    }

    func test_rejectsPolishWords() {
        let d = EnglishTermDetector.shared
        XCTAssertFalse(d.isEnglishTerm("kropka"))
        XCTAssertFalse(d.isEnglishTerm("zażółć"))
        XCTAssertFalse(d.isEnglishTerm("łukasz"))
        XCTAssertFalse(d.isEnglishTerm("dzień"))
    }

    func test_rejectsEmptyAndNonAscii() {
        let d = EnglishTermDetector.shared
        XCTAssertFalse(d.isEnglishTerm(""))
        XCTAssertFalse(d.isEnglishTerm("café"))           // ASCII check
    }
}
