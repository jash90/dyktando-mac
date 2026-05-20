import Foundation

struct PostprocessPipeline {
    let mode: LanguageMode
    let rules: ReplacementRules

    init(mode: LanguageMode, rules: ReplacementRules = .defaults) {
        self.mode = mode
        self.rules = rules
    }

    func apply(_ raw: String) -> String {
        let replaced = rules.apply(raw)
        let punctuated = PunctuationHeuristic.apply(replaced)
        let capitalized = PolishCapitalizer.apply(punctuated)
        return Self.smartSpace(capitalized)
    }

    private static func smartSpace(_ s: String) -> String {
        s.replacingOccurrences(of: " .", with: ".")
         .replacingOccurrences(of: " ,", with: ",")
         .replacingOccurrences(of: " ?", with: "?")
         .replacingOccurrences(of: " !", with: "!")
         .replacingOccurrences(of: " :", with: ":")
         .replacingOccurrences(of: " ;", with: ";")
         .replacingOccurrences(of: "  ", with: " ")
    }
}
