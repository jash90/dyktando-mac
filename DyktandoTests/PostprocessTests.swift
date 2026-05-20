import XCTest
@testable import Dyktando

final class PostprocessTests: XCTestCase {
    // MARK: PolishCapitalizer

    func test_capitalizer_firstAndAfterSentenceEnd() {
        XCTAssertEqual(PolishCapitalizer.apply("dzień dobry. jak się masz?"),
                       "Dzień dobry. Jak się masz?")
    }

    func test_capitalizer_preservesExistingCapitals() {
        XCTAssertEqual(PolishCapitalizer.apply("MacBook to świetny laptop."),
                       "MacBook to świetny laptop.")
    }

    func test_capitalizer_preservesPolishDiacritics() {
        XCTAssertEqual(PolishCapitalizer.apply("żółć i ząb"), "Żółć i ząb")
    }

    // MARK: PunctuationHeuristic

    func test_punctuation_addsDotForLongUtterance() {
        XCTAssertEqual(PunctuationHeuristic.apply("to jest dłuższe zdanie bez kropki"),
                       "to jest dłuższe zdanie bez kropki.")
    }

    func test_punctuation_leavesShortAlone() {
        XCTAssertEqual(PunctuationHeuristic.apply("tak"), "tak")
    }

    func test_punctuation_leavesExisting() {
        XCTAssertEqual(PunctuationHeuristic.apply("ok!"), "ok!")
    }

    // MARK: ReplacementRules

    func test_rules_replaceKropka() {
        XCTAssertEqual(ReplacementRules.defaults.apply("powiedz kropka"), "powiedz .")
    }

    func test_rules_replaceMultiple() {
        let input = "alfa kropka beta przecinek gamma"
        XCTAssertEqual(ReplacementRules.defaults.apply(input), "alfa . beta , gamma")
    }

    func test_rules_skipsAfterEnglishTerm() {
        // "deployment kropka" should NOT replace because "kropka" follows an
        // English term and is probably the literal Polish word, not a marker.
        // (This is opinionated; the rule guards against false positives.)
        let input = "zrób deployment kropka teraz"
        let out = ReplacementRules.defaults.apply(input)
        XCTAssertTrue(out.contains("deployment kropka"),
                      "Got: '\(out)' — expected 'deployment kropka' preserved")
    }

    // MARK: Pipeline composition

    func test_pipeline_endToEnd() {
        let pipeline = PostprocessPipeline(mode: .single(Locale(identifier: "pl-PL")))
        let raw = "dzień dobry kropka jak się masz znak zapytania"
        let out = pipeline.apply(raw)
        XCTAssertEqual(out, "Dzień dobry. Jak się masz?")
    }

    func test_pipeline_smartSpacing() {
        let pipeline = PostprocessPipeline(mode: .single(Locale(identifier: "pl-PL")))
        let raw = "tekst kropka inny tekst przecinek koniec"
        let out = pipeline.apply(raw)
        XCTAssertFalse(out.contains(" ."), "Should remove space before period: \(out)")
        XCTAssertFalse(out.contains(" ,"), "Should remove space before comma: \(out)")
    }
}
