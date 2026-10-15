import Foundation

/// Where the app talks to: the gateway, Keycloak and the web front (for `/demo/...` covers).
///
/// The URLs come from the `WELY_*` build settings, through `Config/Wely-Info.plist`, so the
/// same code points at the local stack in the simulator and at another environment elsewhere.
struct AppConfig: Sendable {
    let gatewayURL: URL
    let keycloakURL: URL
    let webURL: URL

    let realm = "wely-realm"
    let clientId = "wely-client"
    /// The OAuth redirect; Keycloak must list it among `wely-client`'s redirect URIs.
    let redirectURI = "wely://oauth-callback"
    let callbackScheme = "wely"

    var apiURL: URL { gatewayURL.appending(path: "api/v1") }
    /// The chat's RSocket endpoint: the gateway, over WebSocket.
    var rsocketURL: URL {
        var components = URLComponents(url: gatewayURL.appending(path: "rsocket"), resolvingAgainstBaseURL: false)!
        components.scheme = gatewayURL.scheme == "https" ? "wss" : "ws"
        return components.url!
    }
    var realmURL: URL { keycloakURL.appending(path: "realms/\(realm)") }
    var authorizationEndpoint: URL { realmURL.appending(path: "protocol/openid-connect/auth") }
    var tokenEndpoint: URL { realmURL.appending(path: "protocol/openid-connect/token") }
    var logoutEndpoint: URL { realmURL.appending(path: "protocol/openid-connect/logout") }

    static let current = AppConfig(bundle: .main)

    init(gatewayURL: URL, keycloakURL: URL, webURL: URL) {
        self.gatewayURL = gatewayURL
        self.keycloakURL = keycloakURL
        self.webURL = webURL
    }

    init(bundle: Bundle) {
        func url(_ key: String, fallback: String) -> URL {
            let value = bundle.object(forInfoDictionaryKey: key) as? String
            return URL(string: value ?? fallback) ?? URL(string: fallback)!
        }
        self.init(
            gatewayURL: url("WelyGatewayURL", fallback: "http://localhost:8081"),
            keycloakURL: url("WelyKeycloakURL", fallback: "http://localhost:8080"),
            webURL: url("WelyWebURL", fallback: "http://localhost")
        )
    }

    /// An event cover: a signed URL as is, a `/demo/...` path served by the web front.
    func imageURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") { return URL(string: raw, relativeTo: webURL)?.absoluteURL }
        return URL(string: raw)
    }
}
