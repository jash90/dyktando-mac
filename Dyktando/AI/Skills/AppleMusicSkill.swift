import AppKit
import Foundation

/// Opens Apple Music search for the given query via the `music://search`
/// scheme; on macOS this hands off to the Music app and focuses results.
struct AppleMusicSkill: Skill {
    let id = "apple_music_play"
    let description = "wyszukaj i otwórz utwór/album w Apple Music"
    let parameters: [SkillParameter] = [
        SkillParameter("query", "fraza, np. \"mata - patoreakcja\"")
    ]

    func run(params: [String: String]) async throws -> String {
        let query = try require("query", in: params)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "music://music.apple.com/search?term=\(encoded)") else {
            throw SkillError.invalidParam("query", query)
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw SkillError.execution("Nie udało się otworzyć Apple Music") }
        return "Apple Music · \(query)"
    }
}
