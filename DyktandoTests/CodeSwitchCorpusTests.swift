import XCTest
@testable import Dyktando

final class CodeSwitchCorpusTests: XCTestCase {
    func test_corpus_bundled_andNonEmpty() throws {
        let url = Bundle.main.url(forResource: "code_switch_corpus", withExtension: "txt")
        XCTAssertNotNil(url, "code_switch_corpus.txt should be bundled in main app")
        if let url {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.split(separator: "\n").filter { !$0.isEmpty }
            XCTAssertGreaterThanOrEqual(lines.count, 15)
        }
    }

    func test_corpus_containsExpectedEnglishTerms() throws {
        guard let url = Bundle.main.url(forResource: "code_switch_corpus", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return XCTFail("corpus missing")
        }
        let lower = text.lowercased()
        for term in ["deployment", "production", "pull request", "stack overflow",
                     "backend", "docker", "github", "npm install"] {
            XCTAssertTrue(lower.contains(term), "corpus should mention '\(term)'")
        }
    }

    func test_corpus_linesUseEnglishTerms_recognizedByDetector() throws {
        let detector = EnglishTermDetector.shared
        // Sanity: confirm key English terms in the corpus are in the detector's word list.
        for term in ["deployment", "production", "pull", "request", "backend",
                     "docker", "github", "npm", "commit", "merge", "review"] {
            XCTAssertTrue(detector.isEnglishTerm(term),
                          "Detector should recognize '\(term)' from code-switch corpus")
        }
    }
}
