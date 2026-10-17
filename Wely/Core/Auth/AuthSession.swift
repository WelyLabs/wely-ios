import Foundation
import Observation

enum AuthError: LocalizedError, Equatable {
    case cancelled
    case stateMismatch
    case missingCode
    case server(String)
    case sessionExpired
    case invalidCredentials
    case accountNotReady

    var errorDescription: String? {
        switch self {
        case .cancelled: "Connexion annulée."
        case .stateMismatch, .missingCode: "La réponse de connexion est invalide, réessayez."
        case .server(let message): "Connexion impossible : \(message)"
        case .sessionExpired: "Votre session a expiré, reconnectez-vous."
        case .invalidCredentials: "Identifiant ou mot de passe incorrect."
        case .accountNotReady: "Votre compte doit être finalisé (e-mail à vérifier ou mot de passe à changer) : terminez sur la page web de Wely."
        }
    }
}

/// The signed-in state and the tokens behind it.
///
/// Signing in happens on the app's own screen: the username and password go straight to
/// Keycloak's token endpoint (`wely-client` allows direct access grants). Signing up still goes
/// through Keycloak's registration page — its form is what creates the user in wely-users — as
/// the authorization code flow with PKCE: the view opens `registrationURL` in a web
/// authentication session, then hands the callback back to `completeSignIn`. Tokens live in the
/// Keychain and are refreshed shortly before they expire.
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

    /// offline_access: a refresh token that outlives Keycloak's browser session (30 minutes idle),
    /// valid 30 days without use and renewed by each, so closing the app does not sign out.
    static let scope = "openid profile email offline_access"

    /// Signs in with what the user typed on the login screen.
    func signIn(username: String, password: String) async throws {
        lastError = nil
        let tokens: TokenSet
        do {
            tokens = try await requestTokens([
                "grant_type": "password",
                "client_id": config.clientId,
                "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": password,
                "scope": Self.scope,
            ])
        } catch let error as OAuthFailure {
            // Keycloak answers invalid_grant for both a wrong password and an account that still
            // owes a required action (verify the e-mail, change the password): only the
            // description tells them apart.
            if error.code == "invalid_grant" {
                throw error.description?.localizedCaseInsensitiveContains("not fully set up") == true
                    ? AuthError.accountNotReady : AuthError.invalidCredentials
            }
            throw AuthError.server(error.message)
        }
        store(tokens)
        state = .signedIn
    }

    /// Starts a sign-in on a Keycloak page: the URL to open, remembered with its PKCE secret.
    /// `registration` opens the sign-up form instead of the login one.
    func beginSignIn(registration: Bool = false) -> URL {
        let pkce = PKCE()
        pending = pkce
        lastError = nil
        let endpoint = registration ? config.registrationEndpoint : config.authorizationEndpoint
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
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
            try await exchange([
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

/// Keycloak's refusal of a token request, before it becomes an `AuthError`.
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
