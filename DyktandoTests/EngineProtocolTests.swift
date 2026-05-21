import XCTest
@testable import Dyktando

final class EngineProtocolTests: XCTestCase {
    func test_engineID_allCases_hasTwo() {
        XCTAssertEqual(EngineID.allCases.count, 2)
        XCTAssertTrue(EngineID.allCases.contains(.parakeetTDTv3))
        XCTAssertTrue(EngineID.allCases.contains(.appleSpeechPL))
    }

    func test_engineID_rawValues() {
        XCTAssertEqual(EngineID.parakeetTDTv3.rawValue, "parakeet-tdt-v3")
        XCTAssertEqual(EngineID.appleSpeechPL.rawValue, "apple-speech-pl")
    }

    func test_engineID_codable_roundTrip() throws {
        let original = EngineID.parakeetTDTv3
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EngineID.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_transcriptionResult_holdsValues() {
        let r = TranscriptionResult(
            text: "hello",
            language: Locale(identifier: "pl-PL"),
            inferenceMillis: 123,
            confidence: 0.95)
        XCTAssertEqual(r.text, "hello")
        XCTAssertEqual(r.language.identifier, "pl-PL")
        XCTAssertEqual(r.inferenceMillis, 123)
        XCTAssertEqual(r.confidence, 0.95)
    }

    func test_languageMode_equatable() {
        let pl = Locale(identifier: "pl-PL")
        let en = Locale(identifier: "en-US")
        XCTAssertEqual(LanguageMode.single(pl), LanguageMode.single(pl))
        XCTAssertNotEqual(LanguageMode.single(pl), LanguageMode.single(en))
        XCTAssertEqual(LanguageMode.multilingualAuto([pl, en]),
                       LanguageMode.multilingualAuto([en, pl]))
        XCTAssertEqual(LanguageMode.mixed(primary: pl, allowed: [pl, en]),
                       LanguageMode.mixed(primary: pl, allowed: [pl, en]))
        XCTAssertNotEqual(LanguageMode.mixed(primary: pl, allowed: [pl, en]),
                          LanguageMode.mixed(primary: en, allowed: [pl, en]))
    }
}
