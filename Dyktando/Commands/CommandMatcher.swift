import Foundation

enum CommandMatcher {
    /// Normalizes text for trigger comparison: trim, strip trailing
    /// punctuation, fold whitespace, lowercase.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, last.isPunctuation {
            s.removeLast()
        }
        // Collapse runs of internal whitespace.
        s = s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return s.lowercased(with: Locale(identifier: "pl_PL"))
    }
}
