import AppKit
import CryptoKit
import Foundation

/// OAuth 2.0 Authorization Code with PKCE for native desktop apps.
/// Spotify's recommended flow for native clients — no client secret needed.
///
/// Flow:
///   1. Build verifier + challenge (S256), open Spotify auth URL in browser.
///   2. Spotify redirects to `dyktando://spotify-callback?code=…`.
///   3. AppDelegate's URL handler hands the code back here.
///   4. Exchange code → access_token + refresh_token, persist in Keychain.
///   5. From now on `validAccessToken()` returns a fresh token,
///      automatically refreshing when it's close to expiry.
@MainActor
final class SpotifyOAuth: ObservableObject {
    static let shared = SpotifyOAuth()

    static let redirectURI = "dyktando://spotify-callback"
    static let scopes = [
        "user-read-private",         // for /me to greet by display name
        "user-read-playback-state",  // know if there's an active device
        "user-modify-playback-state",// PUT /me/player/play
    ].joined(separator: " ")

    @Published private(set) var displayName: String?
    @Published var lastError: String?

    private var pendingVerifier: String?

    private init() {}

    // MARK: - Public

    var isAuthenticated: Bool { SpotifyTokenStore.current() != nil }

    /// Builds the auth URL and opens it in the default browser. The user
    /// approves access, Spotify redirects to our custom scheme, AppDelegate
    /// catches it and forwards back to `handleCallback(_:)`.
    func startLogin(clientID: String) {
        guard !clientID.isEmpty else {
            lastError = "Brakuje Client ID — wklej go w polu Spotify Client ID."
            return
        }
        let verifier = Self.makeCodeVerifier()
        pendingVerifier = verifier
        let challenge = Self.codeChallenge(for: verifier)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Called from AppDelegate when the system delivers `dyktando://…`.
    func handleCallback(url: URL, clientID: String) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            if let err = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value {
                lastError = "Spotify: \(err)"
            } else {
                lastError = "Spotify: brak parametru 'code' w odpowiedzi"
            }
            return
        }
        guard let verifier = pendingVerifier else {
            lastError = "Spotify: brak verifiera (start login ponownie)"
            return
        }
        pendingVerifier = nil

        do {
            let snapshot = try await exchangeCode(code,
                                                  clientID: clientID,
                                                  verifier: verifier)
            SpotifyTokenStore.save(snapshot)
            await fetchProfile(clientID: clientID)
        } catch {
            lastError = "Spotify exchange: \(error.localizedDescription)"
        }
    }

    func logout() {
        SpotifyTokenStore.clear()
        displayName = nil
    }

    /// Returns a fresh access token, refreshing transparently when expired.
    /// Throws if no token is stored or the refresh fails.
    func validAccessToken(clientID: String) async throws -> String {
        guard let snap = SpotifyTokenStore.current() else {
            throw SpotifyAuthError.notAuthenticated
        }
        if !snap.isExpired { return snap.accessToken }
        let refreshed = try await refresh(snap.refreshToken, clientID: clientID)
        SpotifyTokenStore.save(refreshed)
        return refreshed.accessToken
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String,
                              clientID: String,
                              verifier: String) async throws -> SpotifyTokenStore.Snapshot {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.expect2xx(response, data: data)
        return try Self.decodeTokenResponse(data: data, fallbackRefresh: nil)
    }

    private func refresh(_ refreshToken: String,
                         clientID: String) async throws -> SpotifyTokenStore.Snapshot {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.expect2xx(response, data: data)
        // Spotify may or may not rotate the refresh token. If it's missing
        // from the response, reuse the previous one so the user stays
        // logged in.
        return try Self.decodeTokenResponse(data: data, fallbackRefresh: refreshToken)
    }

    private func fetchProfile(clientID: String) async {
        do {
            let token = try await validAccessToken(clientID: clientID)
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                displayName = (json["display_name"] as? String) ?? (json["id"] as? String)
            }
        } catch {
            NSLog("[Spotify] profile fetch failed: %@", "\(error)")
        }
    }

    // MARK: - PKCE helpers

    private static func makeCodeVerifier() -> String {
        // 64 bytes of randomness → base64url ≈ 86 chars (within 43–128 spec).
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    private static func formEncode(_ params: [String: String]) -> String {
        params.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }.joined(separator: "&")
    }

    private static func expect2xx(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyAuthError.http(status: http.statusCode, body: body)
        }
    }

    private static func decodeTokenResponse(data: Data,
                                            fallbackRefresh: String?) throws -> SpotifyTokenStore.Snapshot {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = resp.refresh_token ?? fallbackRefresh else {
            throw SpotifyAuthError.malformedResponse("missing refresh_token")
        }
        return SpotifyTokenStore.Snapshot(
            accessToken: resp.access_token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(resp.expires_in))
        )
    }
}

enum SpotifyAuthError: LocalizedError {
    case notAuthenticated
    case http(status: Int, body: String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:     return "Najpierw połącz się ze Spotify w Settings → AI."
        case .http(let s, let b):   return "Spotify HTTP \(s): \(b)"
        case .malformedResponse(let m): return "Spotify malformed response: \(m)"
        }
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
