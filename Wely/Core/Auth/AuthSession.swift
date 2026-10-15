import Foundation
import Observation

enum AuthError: LocalizedError, Equatable {
    case cancelled
    case stateMismatch
    case missingCode
    case server(String)
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .cancelled: "Connexion annulée."
        case .stateMismatch, .missingCode: "La réponse de connexion est invalide, réessayez."
        case .server(let message): "Connexion impossible : \(message)"
        case .sessionExpired: "Votre session a expiré, reconnectez-vous."
        }
    }
}

/// The signed-in state and the tokens behind it.
///
/// Signing in is Keycloak's authorization code flow with PKCE: the view opens
/// `authorizationURL` in a web authentication session, then hands the callback back to
/// `completeSignIn`. Tokens live in the Keychain and are refreshed shortly before they expire.
@Observable
final class AuthSession {
    enum State: Equatable {
        case signedOut
        case signedIn
    }

    private(set) var state: State
    var lastError: AuthError?

    @ObservationIgnored let config: AppConfig
    @ObservationIgnored private let store: TokenStore
    @ObservationIgnored private let http: HTTPTransport
    @ObservationIgnored private var tokens: TokenSet?
    @ObservationIgnored private var pending: PKCE?
    @ObservationIgnored private var refreshTask: Task<TokenSet, Error>?

    init(config: AppConfig = .current, store: TokenStore = KeychainTokenStore(), http: HTTPTransport = URLSession.shared) {
        self.config = config
        self.store = store
        self.http = http
        self.tokens = store.load()
        self.state = tokens == nil ? .signedOut : .signedIn
    }

    // MARK: Sign in

    /// Starts a sign-in: the Keycloak page to open, remembered with its PKCE secret.
    func beginSignIn() -> URL {
        let pkce = PKCE()
        pending = pkce
        lastError = nil
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid profile email"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    /// Ends a sign-in with Keycloak's redirect: checks the state, trades the code for tokens.
    func completeSignIn(callback: URL) async throws {
        guard let pkce = pending else { throw AuthError.stateMismatch }
        pending = nil
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw AuthError.server(value("error_description") ?? error)
        }
        guard value("state") == pkce.state else { throw AuthError.stateMismatch }
        guard let code = value("code") else { throw AuthError.missingCode }

        let tokens = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientId,
            "code_verifier": pkce.verifier,
        ])
        store(tokens)
        state = .signedIn
    }

    func fail(_ error: AuthError) {
        pending = nil
        lastError = error
    }

    // MARK: Tokens

    /// An access token good for at least 30 more seconds, refreshed when needed.
    func validAccessToken() async throws -> String {
        guard let tokens else { throw AuthError.sessionExpired }
        if !tokens.isExpiring() { return tokens.accessToken }
        return try await refresh().accessToken
    }

    /// Trades the refresh token for new tokens; concurrent callers share one request.
    @discardableResult
    func refresh() async throws -> TokenSet {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokens?.refreshToken else {
            expire()
            throw AuthError.sessionExpired
        }
        let task = Task {
            try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": config.clientId,
            ])
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            store(fresh)
            return fresh
        } catch {
            expire()
            throw AuthError.sessionExpired
        }
    }

    // MARK: Sign out

    /// Forgets the session here and, best effort, ends it in Keycloak.
    func signOut() async {
        let refreshToken = tokens?.refreshToken
        clearSession()
        guard let refreshToken else { return }
        var request = URLRequest(url: config.logoutEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(["client_id": config.clientId, "refresh_token": refreshToken])
        _ = try? await http.data(for: request)
    }

    /// The session is gone (refresh refused): back to the sign-in screen with a word why.
    func expire() {
        clearSession()
        lastError = .sessionExpired
    }

    private func clearSession() {
        tokens = nil
        store.clear()
        state = .signedOut
    }

    private func store(_ tokens: TokenSet) {
        self.tokens = tokens
        store.save(tokens)
    }

    private func requestTokens(_ form: [String: String]) async throws -> TokenSet {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form)
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(OAuthError.self, from: data))?.message
            throw AuthError.server(message ?? "HTTP \(response.statusCode)")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).tokenSet()
    }

    static func formBody(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

private struct OAuthError: Decodable {
    let error: String
    let errorDescription: String?

    var message: String { errorDescription ?? error }

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
