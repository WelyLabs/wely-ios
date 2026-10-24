import Foundation

/// Where the app talks to: the gateway, Keycloak and the web front (for `/demo/...` covers).
///
/// The URLs come from the `WELY_*` build settings, through `Config/Wely-Info.plist`, so the
/// same code points at the local stack in the simulator and at another environment elsewhere.
struct AppConfig: Sendable {
    let gatewayURL: URL
    let keycloakURL: URL
    let webURL: URL

    /// This environment's realm, `wely-<env>`: one Keycloak serves them all.
    let realm: String
    /// This environment's client, `wely-<service>-<env>-client`.
    let clientId: String
    /// The OAuth redirect; Keycloak must list it among this client's redirect URIs.
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
    var registrationEndpoint: URL { realmURL.appending(path: "protocol/openid-connect/registrations") }
    /// Keycloak's « forgotten password » form, which sends the reset link by e-mail.
    var resetPasswordURL: URL {
        var components = URLComponents(url: realmURL.appending(path: "login-actions/reset-credentials"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "client_id", value: clientId)]
        return components.url!
    }
    var tokenEndpoint: URL { realmURL.appending(path: "protocol/openid-connect/token") }
    var logoutEndpoint: URL { realmURL.appending(path: "protocol/openid-connect/logout") }

    static let current = AppConfig(bundle: .main)

    init(gatewayURL: URL, keycloakURL: URL, webURL: URL,
         realm: String = "wely-local", clientId: String = "wely-web-local-client") {
        self.gatewayURL = gatewayURL
        self.keycloakURL = keycloakURL
        self.webURL = webURL
        self.realm = realm
        self.clientId = clientId
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
            keycloakURL: url("WelyKeycloakURL", fallback: "http://localhost:8080"),
            webURL: url("WelyWebURL", fallback: "http://localhost"),
            realm: text("WelyKeycloakRealm", fallback: "wely-local"),
            clientId: text("WelyKeycloakClientId", fallback: "wely-web-local-client")
        )
    }

    /// An event cover: a signed URL as is, a `/demo/...` path served by the web front.
    func imageURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") { return URL(string: raw, relativeTo: webURL)?.absoluteURL }
        return URL(string: raw)
    }
}
