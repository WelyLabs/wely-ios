import Foundation
import Observation

enum AuthError: LocalizedError, Equatable {
    case cancelled
    case stateMismatch
    case missingCode
    case server(String)
    case sessionExpired
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .cancelled: "Connexion annulée."
        case .stateMismatch, .missingCode: "La réponse de connexion est invalide, réessayez."
        case .server(let message): "Connexion impossible : \(message)"
        case .sessionExpired: "Votre session a expiré, reconnectez-vous."
        case .invalidCredentials: "Identifiant ou mot de passe incorrect."
        }
    }
}

/// The signed-in state and the tokens behind it.
///
/// Signing in happens on the app's own screen: the username and password go straight to
/// Auth0's token endpoint (the Native application allows the password grant). Signing up, a
/// forgotten password, and Google or GitHub sign-in (which the password grant cannot do) go through Auth0's Universal Login as the authorization code flow with
/// PKCE: the view opens `beginSignIn` in a web authentication session, then hands the callback
/// back to `completeSignIn`. Tokens live in the Keychain and are refreshed shortly before they expire.
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

    /// offline_access: a refresh token, so closing the app does not sign out.
    static let scope = "openid profile email offline_access"

    /// Signs in with what the user typed on the login screen.
    func signIn(username: String, password: String) async throws {
        lastError = nil
        let tokens: TokenSet
        do {
            tokens = try await requestTokens([
                // password-realm names the connection, so no tenant-wide Default Directory is needed.
                "grant_type": "http://auth0.com/oauth/grant-type/password-realm",
                "realm": config.connection,
                "client_id": config.clientId,
                "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": password,
                "scope": Self.scope,
                "audience": config.audience,
            ])
        } catch let error as OAuthFailure {
            if error.code == "invalid_grant" { throw AuthError.invalidCredentials }
            throw AuthError.server(error.message)
        }
        store(tokens)
        state = .signedIn
    }

    /// Starts a sign-in on Auth0's Universal Login: the URL to open, remembered with its PKCE secret.
    /// `signUp` opens the sign-up screen instead of the login one, which offers « forgot password ».
    /// `connection` skips the login page for that identity provider (`google-oauth2`, `github`);
    /// `forceLogin` asks for the credentials again even with a live session (`prompt=login`).
    func beginSignIn(signUp: Bool = false, connection: String? = nil, forceLogin: Bool = false) -> URL {
        let pkce = PKCE()
        pending = pkce
        lastError = nil
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "audience", value: config.audience),
        ]
        if signUp { components.queryItems?.append(URLQueryItem(name: "screen_hint", value: "signup")) }
        if let connection { components.queryItems?.append(URLQueryItem(name: "connection", value: connection)) }
        if forceLogin { components.queryItems?.append(URLQueryItem(name: "prompt", value: "login")) }
        return components.url!
    }

    /// Ends a sign-in with Auth0's redirect: checks the state, trades the code for tokens.
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

        let tokens = try await exchange([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientId,
            "code_verifier": pkce.verifier,
        ])
        store(tokens)
        state = .signedIn
    }

    /// The Auth0 connection of a user signed in through Google or GitHub, read from the access
    /// token's `sub` (`google-oauth2|…`); nil for a password account (`auth0|…`) or no session.
    var socialConnection: String? {
        tokens.flatMap { Self.socialConnection(ofAccessToken: $0.accessToken) }
    }

    static func socialConnection(ofAccessToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = claims["sub"] as? String,
              !subject.hasPrefix("auth0|"),
              let separator = subject.firstIndex(of: "|") else { return nil }
        return String(subject[..<separator])
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
        // A network error (no signal yet when the app comes back) passes through: the session stays.
        do {
            var fresh = try await task.value
            // Without rotation Auth0 does not resend the refresh token: keep the one we have.
            if fresh.refreshToken == nil {
                fresh = TokenSet(accessToken: fresh.accessToken, refreshToken: refreshToken, idToken: fresh.idToken, expiresAt: fresh.expiresAt)
            }
            store(fresh)
            return fresh
        } catch let error as OAuthFailure where error.status == 400 || error.status == 401 || error.code == "invalid_grant" {
            // Auth0 refused the refresh token (403 invalid_grant): revoked, reused, or expired.
            expire()
            throw AuthError.sessionExpired
        } catch let error as OAuthFailure {
            // Auth0 unreachable, a 5xx: the session is still good.
            throw AuthError.server(error.message)
        }
    }

    /// Picks up a session the Keychain would not give at launch: iOS may start the app before
    /// the phone was first unlocked (prewarming after a restart), when the Keychain is still sealed.
    func restore() {
        guard state == .signedOut, tokens == nil, pending == nil, let saved = store.load() else { return }
        tokens = saved
        lastError = nil
        state = .signedIn
    }

    // MARK: Sign out

    /// Forgets the session here and, best effort, revokes the refresh token at Auth0. Not
    /// `/oidc/logout`: the web sessions are ephemeral, so no Auth0 cookie survives to end.
    func signOut() async {
        let refreshToken = tokens?.refreshToken
        clearSession()
        guard let refreshToken else { return }
        var request = URLRequest(url: config.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(["client_id": config.clientId, "token": refreshToken])
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

    /// A token request whose failure is an `AuthError`.
    private func exchange(_ form: [String: String]) async throws -> TokenSet {
        do {
            return try await requestTokens(form)
        } catch let error as OAuthFailure {
            throw AuthError.server(error.message)
        }
    }

    private func requestTokens(_ form: [String: String]) async throws -> TokenSet {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form)
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONDecoder().decode(OAuthError.self, from: data)
            throw OAuthFailure(code: body?.error, description: body?.errorDescription, status: response.statusCode)
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

/// Auth0's refusal of a token request, before it becomes an `AuthError`.
private struct OAuthFailure: Error {
    let code: String?
    let description: String?
    let status: Int

    var message: String { description ?? code ?? "HTTP \(status)" }
}

private struct OAuthError: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
