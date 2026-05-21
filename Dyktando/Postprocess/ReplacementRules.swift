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

    /// Replaces dictation markers wherever they appear as separate words,
    /// surrounded by whitespace. Surrounding spaces are preserved so the
    /// smartSpace pass in PostprocessPipeline can remove the stray
    /// space-before-punctuation cleanly afterwards.
    func apply(_ text: String) -> String {
        var out = " " + text + " "
        for (marker, replacement) in pairs {
            let pattern = " \(marker) "
            while let range = out.range(of: pattern) {
                out.replaceSubrange(range, with: " \(replacement) ")
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
