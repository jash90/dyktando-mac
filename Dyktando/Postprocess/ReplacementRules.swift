import Foundation

struct ReplacementRules {
    let pairs: [(String, String)]

    static let defaults = ReplacementRules(pairs: [
        ("kropka", "."),
        ("przecinek", ","),
        ("znak zapytania", "?"),
        ("wykrzyknik", "!"),
        ("nowa linia", "\n"),
        ("nowy akapit", "\n\n"),
        ("dwukropek", ":"),
        ("średnik", ";"),
    ])

    /// Replaces dictation markers wherever they appear as separate words.
    /// Skips matches that are immediately preceded by an English term so
    /// `merge request kropka` still works but `deployment kropka` doesn't
    /// swallow a real word.
    func apply(_ text: String) -> String {
        var out = " " + text + " "  // pad for boundary checks
        for (marker, replacement) in pairs {
            // Match the marker surrounded by whitespace boundaries.
            let pattern = " \(marker) "
            while let range = out.range(of: pattern) {
                // Look at the text before the leading space of the pattern
                // to find the previous word.
                let before = out[..<range.lowerBound]
                let prevToken = String(before.split(whereSeparator: { $0.isWhitespace }).last ?? "")
                if EnglishTermDetector.shared.isEnglishTerm(prevToken) {
                    // Don't replace if it follows an English code term.
                    // Skip this occurrence by replacing with a temp sentinel,
                    // we'll restore at the end.
                    let sentinel = "\u{0001}\(marker)\u{0001}"
                    out.replaceSubrange(range,
                                        with: " \(sentinel) ")
                    continue
                }
                // Preserve surrounding spaces so adjacent words stay separated;
                // smartSpace in PostprocessPipeline will remove any spurious
                // space-before-punctuation later.
                out.replaceSubrange(range, with: " \(replacement) ")
            }
            // Restore sentinels back to the original marker.
            out = out.replacingOccurrences(of: "\u{0001}\(marker)\u{0001}", with: marker)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
