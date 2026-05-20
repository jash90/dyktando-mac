import XCTest
@testable import Dyktando

final class LanguageModeCodecTests: XCTestCase {
    func test_single_roundTrip() {
        let original = LanguageMode.single(Locale(identifier: "pl-PL"))
        XCTAssertEqual(LanguageModeCodec.decode(LanguageModeCodec.encode(original)), original)
    }

    func test_multilingualAuto_roundTrip() {
        let original = LanguageMode.multilingualAuto([
            Locale(identifier: "pl-PL"),
            Locale(identifier: "en-US")
        ])
        XCTAssertEqual(LanguageModeCodec.decode(LanguageModeCodec.encode(original)), original)
    }

    func test_mixed_roundTrip() {
        let original = LanguageMode.mixed(
            primary: Locale(identifier: "pl-PL"),
            allowed: [Locale(identifier: "pl-PL"), Locale(identifier: "en-US")]
        )
        XCTAssertEqual(LanguageModeCodec.decode(LanguageModeCodec.encode(original)), original)
    }
}
