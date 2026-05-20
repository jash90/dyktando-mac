import Foundation

enum LanguageModeCodec {
    static func encode(_ mode: LanguageMode) -> String {
        switch mode {
        case .single(let l):
            return "single:\(l.identifier)"
        case .multilingualAuto(let langs):
            return "multi:" + langs.map(\.identifier).sorted().joined(separator: ",")
        case .mixed(let primary, let langs):
            return "mixed:\(primary.identifier)/" + langs.map(\.identifier).sorted().joined(separator: ",")
        }
    }

    static func decode(_ s: String) -> LanguageMode {
        if s.hasPrefix("single:") {
            return .single(Locale(identifier: String(s.dropFirst("single:".count))))
        }
        if s.hasPrefix("multi:") {
            let langs = s.dropFirst("multi:".count)
                .split(separator: ",")
                .map { Locale(identifier: String($0)) }
            return .multilingualAuto(Set(langs))
        }
        if s.hasPrefix("mixed:") {
            let rest = s.dropFirst("mixed:".count)
            let parts = rest.split(separator: "/")
            guard parts.count == 2 else { return .single(Locale(identifier: "pl-PL")) }
            let primary = Locale(identifier: String(parts[0]))
            let langs = parts[1]
                .split(separator: ",")
                .map { Locale(identifier: String($0)) }
            return .mixed(primary: primary, allowed: Set(langs))
        }
        return .single(Locale(identifier: "pl-PL"))
    }
}
