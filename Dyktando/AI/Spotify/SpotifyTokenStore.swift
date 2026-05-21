import Foundation
import Security

/// Keychain-backed storage for the Spotify access + refresh tokens. Tokens
/// are stored under the user's login keychain with the app's bundle id as
/// the service, so they survive app reinstalls cleanly and aren't visible
/// in plist defaults.
enum SpotifyTokenStore {
    private static let service = "com.bartekzimny.dyktando.spotify"
    private static let accessAccount = "access_token"
    private static let refreshAccount = "refresh_token"
    private static let expiresAccount = "expires_at"   // ISO8601 string

    struct Snapshot: Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date

        var isExpired: Bool {
            // Treat as expired ≥60 s before the real wall-clock to give the
            // refresh round-trip time to land before a request.
            Date().addingTimeInterval(60) >= expiresAt
        }
    }

    // MARK: - Save / Load

    static func save(_ snapshot: Snapshot) {
        write(snapshot.accessToken, account: accessAccount)
        write(snapshot.refreshToken, account: refreshAccount)
        write(ISO8601DateFormatter().string(from: snapshot.expiresAt),
              account: expiresAccount)
    }

    static func current() -> Snapshot? {
        guard let access = read(account: accessAccount),
              let refresh = read(account: refreshAccount),
              let expiresStr = read(account: expiresAccount),
              let expires = ISO8601DateFormatter().date(from: expiresStr) else {
            return nil
        }
        return Snapshot(accessToken: access, refreshToken: refresh, expiresAt: expires)
    }

    static func clear() {
        for account in [accessAccount, refreshAccount, expiresAccount] {
            delete(account: account)
        }
    }

    // MARK: - Low-level keychain

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
