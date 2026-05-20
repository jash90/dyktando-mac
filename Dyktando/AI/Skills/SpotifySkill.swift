import AppKit
import Foundation

/// Opens Spotify's search results for the given query. We use the
/// `spotify:` URI scheme (the desktop app focuses its search box and shows
/// matching artists/albums/tracks). Without OAuth we can't drive playback
/// directly, but the user gets one click away.
struct SpotifySkill: Skill {
    let id = "spotify_play"
    let description = "odtwórz utwór, album lub artystę na Spotify (otwiera wyszukiwanie)"
    let parameters: [SkillParameter] = [
        SkillParameter("query", "fraza do wyszukania, np. nazwa artysty lub albumu")
    ]

    func run(params: [String: String]) async throws -> String {
        let query = try require("query", in: params)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "spotify:search:\(encoded)") else {
            throw SkillError.invalidParam("query", query)
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw SkillError.execution("Nie udało się otworzyć Spotify") }
        return "Spotify · \(query)"
    }
}
