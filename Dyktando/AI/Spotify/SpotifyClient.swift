import Foundation

/// Spotify Web API wrapper for the two operations we need from the dictation
/// flow: search albums/tracks by query, and start playback on the user's
/// currently active device.
///
/// Every call routes through `SpotifyOAuth.validAccessToken(clientID:)` which
/// transparently refreshes the access token when it's close to expiring.
struct SpotifyClient {
    let oauth: SpotifyOAuth
    let clientID: String

    @MainActor
    init(oauth: SpotifyOAuth = .shared, clientID: String) {
        self.oauth = oauth
        self.clientID = clientID
    }

    // MARK: - Search

    enum SearchKind: String {
        case album, track, artist
    }

    struct SearchResult {
        let uri: String        // spotify:album:… / spotify:track:… / spotify:artist:…
        let name: String
        let artist: String?
    }

    /// First-match search across the chosen entity. The Web API is fuzzy
    /// enough that "mata" (genitive of "Mata") still hits the artist.
    func searchFirst(query: String, kind: SearchKind) async throws -> SearchResult? {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: kind.rawValue),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "market", value: "from_token"),
        ]
        guard let url = components.url else { return nil }

        let data = try await get(url)
        return Self.parseFirstResult(from: data, kind: kind)
    }

    // MARK: - Playback

    /// Starts (or resumes) playback on the user's active device.
    /// `contextURI` should point at an album/playlist/artist.
    /// Spotify requires Premium; otherwise this throws a 403.
    func play(contextURI: String) async throws {
        var request = try await authedRequest(
            url: URL(string: "https://api.spotify.com/v1/me/player/play")!,
            method: "PUT"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context_uri": contextURI,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try ensure2xx(response, data: data)
    }

    /// "Play the latest album by <artist>" composite: search artist → fetch
    /// their latest album → start playback. Returns a tuple suitable for a
    /// HUD preview.
    func playLatestAlbum(byArtist query: String) async throws -> (album: String, artist: String) {
        guard let artist = try await searchFirst(query: query, kind: .artist) else {
            throw NSError(domain: "Spotify", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Nie znalazłem artysty '\(query)' na Spotify"])
        }
        let artistID = artist.uri.split(separator: ":").last.map(String.init) ?? ""
        var components = URLComponents(string: "https://api.spotify.com/v1/artists/\(artistID)/albums")!
        components.queryItems = [
            URLQueryItem(name: "include_groups", value: "album,single"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "market", value: "from_token"),
        ]
        guard let url = components.url else {
            throw NSError(domain: "Spotify", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Bad artist albums URL"])
        }
        let data = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let first = items.first,
              let uri = first["uri"] as? String,
              let name = first["name"] as? String else {
            throw NSError(domain: "Spotify", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Brak albumów artysty '\(artist.name)'"])
        }
        try await play(contextURI: uri)
        return (album: name, artist: artist.name)
    }

    // MARK: - HTTP helpers

    private func get(_ url: URL) async throws -> Data {
        let request = try await authedRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try ensure2xx(response, data: data)
        return data
    }

    private func authedRequest(url: URL, method: String) async throws -> URLRequest {
        let token = try await oauth.validAccessToken(clientID: clientID)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func ensure2xx(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            // 403 = playback API requires Premium. 404 = no active device.
            // Surface those distinctly because the user-facing fix differs.
            if http.statusCode == 403, body.contains("Premium") {
                throw NSError(domain: "Spotify", code: 403,
                              userInfo: [NSLocalizedDescriptionKey: "Spotify Web API odtwarzania wymaga konta Premium."])
            }
            if http.statusCode == 404, body.contains("NO_ACTIVE_DEVICE") {
                throw NSError(domain: "Spotify", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "Nie ma aktywnego urządzenia Spotify. Uruchom aplikację Spotify i zacznij coś odtwarzać, potem powtórz."])
            }
            throw NSError(domain: "Spotify", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Spotify HTTP \(http.statusCode): \(body)"])
        }
    }

    // MARK: - Parsing

    private static func parseFirstResult(from data: Data, kind: SearchKind) -> SearchResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let listKey: String
        switch kind {
        case .album:  listKey = "albums"
        case .track:  listKey = "tracks"
        case .artist: listKey = "artists"
        }
        guard let container = root[listKey] as? [String: Any],
              let items = container["items"] as? [[String: Any]],
              let first = items.first,
              let uri = first["uri"] as? String,
              let name = first["name"] as? String else {
            return nil
        }
        let artistName: String?
        if let artists = first["artists"] as? [[String: Any]] {
            artistName = artists.compactMap { $0["name"] as? String }
                .joined(separator: ", ")
        } else {
            artistName = nil
        }
        return SearchResult(uri: uri, name: name, artist: artistName)
    }
}
