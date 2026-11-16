import Foundation

/// Where the app talks to: the gateway, Auth0 and the web front (for `/demo/...` covers).
///
/// The URLs come from the `WELY_*` build settings, through `Config/Wely-Info.plist`, so the
/// same code points at the local stack in the simulator and at another environment elsewhere.
struct AppConfig: Sendable {
    let gatewayURL: URL
    /// The Auth0 tenant's domain, without scheme.
    let authDomain: String
    let webURL: URL

    /// This environment's Auth0 Native application, `wely-ios-<env>`.
    let clientId: String
    /// This environment's API identifier, `wely-api-<env>`: without it Auth0 hands out an opaque token.
    let audience: String
    /// This environment's database connection, `wely-<env>-users`: the password grant's `realm`.
    let connection: String
    /// The OAuth redirect; Auth0 must list it among this application's callback URLs.
    let redirectURI = "wely://oauth-callback"
    let callbackScheme = "wely"

    var apiURL: URL { gatewayURL.appending(path: "api/v1") }
    /// The chat's RSocket endpoint: the gateway, over WebSocket.
    var rsocketURL: URL {
        var components = URLComponents(url: gatewayURL.appending(path: "rsocket"), resolvingAgainstBaseURL: false)!
        components.scheme = gatewayURL.scheme == "https" ? "wss" : "ws"
        return components.url!
    }
    var authURL: URL { URL(string: "https://\(authDomain)")! }
    var authorizationEndpoint: URL { authURL.appending(path: "authorize") }
    var tokenEndpoint: URL { authURL.appending(path: "oauth/token") }
    var revocationEndpoint: URL { authURL.appending(path: "oauth/revoke") }

    static let current = AppConfig(bundle: .main)

    init(gatewayURL: URL, authDomain: String, webURL: URL,
         clientId: String = "wely-ios-test", audience: String = "wely-api-test", connection: String = "wely-test-users") {
        self.gatewayURL = gatewayURL
        self.authDomain = authDomain
        self.webURL = webURL
        self.clientId = clientId
        self.audience = audience
        self.connection = connection
    }

    init(bundle: Bundle) {
        func url(_ key: String, fallback: String) -> URL {
            let value = bundle.object(forInfoDictionaryKey: key) as? String
            return URL(string: value ?? fallback) ?? URL(string: fallback)!
        }
        // An unset build setting leaves the plist holding "$(WELY_...)", which is not a name.
        func text(_ key: String, fallback: String) -> String {
            let value = bundle.object(forInfoDictionaryKey: key) as? String
            guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return fallback }
            return value
        }
        self.init(
            gatewayURL: url("WelyGatewayURL", fallback: "http://localhost:8081"),
            authDomain: text("WelyAuthDomain", fallback: "auth.welylabs.app"),
            webURL: url("WelyWebURL", fallback: "http://localhost"),
            clientId: text("WelyAuthClientId", fallback: "B13EYAgwz0taFojKXvElwbGUQfVkiNkS"),
            audience: text("WelyAuthAudience", fallback: "wely-api-dev"),
            connection: text("WelyAuthConnection", fallback: "wely-dev-users")
        )
    }

    /// An event cover: a signed URL as is, a `/demo/...` path served by the web front.
    func imageURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") { return URL(string: raw, relativeTo: webURL)?.absoluteURL }
        return URL(string: raw)
    }
}
