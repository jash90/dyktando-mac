import Foundation

enum PolishCapitalizer {
    /// Capitalizes the first letter, and the first letter after every sentence
    /// terminator (`.`, `!`, `?`). Preserves existing capitals and Polish diacritics.
    static func apply(_ text: String) -> String {
        var out = ""
        var capitalizeNext = true
        for ch in text {
            if capitalizeNext, ch.isLetter {
                out.append(Character(ch.uppercased()))
                capitalizeNext = false
            } else {
                out.append(ch)
            }
            if ".!?".contains(ch) { capitalizeNext = true }
        }
        return out
    }
}
