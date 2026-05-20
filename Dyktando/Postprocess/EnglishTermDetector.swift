import Foundation

final class EnglishTermDetector: @unchecked Sendable {
    static let shared = EnglishTermDetector()
    private let set: Set<String>

    private init() {
        guard let url = Bundle.main.url(forResource: "english_terms", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            self.set = []
            return
        }
        self.set = Set(
            text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    /// Returns true iff the given token is an ASCII-only word found in the
    /// bundled English-terms dictionary. Used to skip Polish-only post-processing
    /// rules for English code-switched words.
    func isEnglishTerm(_ word: String) -> Bool {
        guard !word.isEmpty, word.allSatisfy({ $0.isASCII }) else { return false }
        return set.contains(word.lowercased())
    }
}
