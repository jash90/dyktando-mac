import AppKit
import Foundation

/// Opens a web search for the user's query in the default browser via
/// DuckDuckGo (no tracking, no API key, works offline-friendly).
struct WebSearchSkill: Skill {
    let id = "web_search"
    let description = "wyszukaj w internecie i otwórz wyniki w domyślnej przeglądarce"
    let parameters: [SkillParameter] = [
        SkillParameter("query", "co wyszukać")
    ]

    func run(params: [String: String]) async throws -> String {
        let query = try require("query", in: params)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://duckduckgo.com/?q=\(encoded)") else {
            throw SkillError.invalidParam("query", query)
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw SkillError.execution("Nie udało się otworzyć przeglądarki") }
        return "🔎 \(query)"
    }
}
