import Foundation
import Security

/// The tokens Keycloak hands out, with the access token's expiry made absolute.
struct TokenSet: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresAt: Date

    /// True when the access token expires within `margin` seconds.
    func isExpiring(within margin: TimeInterval = 30, now: Date = .now) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
    }
}

/// Keycloak's token endpoint answer.
struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }

    func tokenSet(issuedAt: Date = .now) -> TokenSet {
        TokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresAt: issuedAt.addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}

/// Where the session survives a relaunch.
protocol TokenStore: Sendable {
    func load() -> TokenSet?
    func save(_ tokens: TokenSet)
    func clear()
}

/// The tokens in the Keychain, readable once the phone was unlocked after starting up: the app
/// is also woken locked (a call, prewarming), and must still find its session then.
struct KeychainTokenStore: TokenStore {
    var service = "com.welylabs.wely.auth"
    var account = "tokens"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> TokenSet? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    func save(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        clear()
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// A store that forgets everything on relaunch: previews, tests and the demo mode.
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var tokens: TokenSet?
    init(_ tokens: TokenSet? = nil) { self.tokens = tokens }
    func load() -> TokenSet? { tokens }
    func save(_ tokens: TokenSet) { self.tokens = tokens }
    func clear() { tokens = nil }
}
