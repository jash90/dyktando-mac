import AppKit
import Foundation

/// Plays music on Spotify.
///
/// Two paths:
///   • Authenticated (OAuth via Settings → AI → Spotify): uses the Web API
///     to find the latest album by the requested artist and start playback
///     on the active device. Requires Spotify Premium.
///   • Unauthenticated: falls back to the `spotify:search:` URI scheme,
///     which opens the Spotify desktop app focused on the search results.
struct SpotifySkill: Skill {
    let id = "spotify_play"
    let description = "odtwórz utwór, album lub artystę na Spotify (po OAuth — realne odtwarzanie; bez — otwiera wyszukiwanie)"
    let parameters: [SkillParameter] = [
        SkillParameter("query", "fraza do wyszukania, np. nazwa artysty lub albumu")
    ]

    func run(params: [String: String]) async throws -> String {
        let query = try require("query", in: params)
        let (clientID, hasToken) = await MainActor.run {
            (Preferences.shared.spotifyClientID, SpotifyOAuth.shared.isAuthenticated)
        }

        if hasToken, !clientID.isEmpty {
            do {
                let client = await MainActor.run { SpotifyClient(clientID: clientID) }
                let result = try await client.playLatestAlbum(byArtist: query)
                return "▶ \(result.artist) — \(result.album)"
            } catch {
                // Fall through to URL-scheme search so the user still gets
                // *something* useful instead of a hard failure.
                NSLog("[Spotify] API path failed, falling back to search: %@",
                      "\(error)")
                let url = try Self.makeSearchURL(query: query)
                _ = await MainActor.run { NSWorkspace.shared.open(url) }
                return "Spotify · \(query) (\(error.localizedDescription))"
            }
        }

        // No OAuth → search URI.
        let url = try Self.makeSearchURL(query: query)
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw SkillError.execution("Nie udało się otworzyć Spotify") }
        return "Spotify · \(query)"
    }

    private static func makeSearchURL(query: String) throws -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "spotify:search:\(encoded)") else {
            throw SkillError.invalidParam("query", query)
        }
        return url
    }
}
