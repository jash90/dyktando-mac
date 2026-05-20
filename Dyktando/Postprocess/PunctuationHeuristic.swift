import Foundation

enum PunctuationHeuristic {
    /// Adds a trailing `.` when the input has no sentence terminator and is
    /// longer than a short utterance (>6 words). Whisper already emits
    /// punctuation; Parakeet often doesn't, hence this safety net.
    static func apply(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return text }
        if ".!?".contains(last) { return trimmed }
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        return wordCount >= 6 ? trimmed + "." : trimmed
    }
}
