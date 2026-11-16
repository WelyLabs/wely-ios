import Foundation
import Testing
@testable import Wely

/// Answers every request with the next canned response and records what was sent; a status of
/// -1 is a request that never reached the server.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = responses.isEmpty ? (500, "") : responses.removeFirst()
        if status == -1 { throw URLError(.notConnectedToInternet) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func form(_ index: Int) -> [String: String] {
        let body = String(data: requests[index].httpBody ?? Data(), encoding: .utf8) ?? ""
        return Dictionary(uniqueKeysWithValues: body.split(separator: "&").map {
            let pair = $0.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            return (pair[0], pair.count > 1 ? pair[1] : "")
        })
    }
}

private let tokenJSON = #"{"access_token":"AT","refresh_token":"RT","id_token":"IT","expires_in":300}"#
private let config = AppConfig(gatewayURL: URL(string: "http://gw")!, authDomain: "kc", webURL: URL(string: "http://web")!)

struct PKCETests {
    @Test func challengeIsTheRFCExample() {
        // RFC 7636, appendix B.
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomStringsAreURLSafeAndDistinct() {
        let a = PKCE.randomString(), b = PKCE.randomString()
        #expect(a != b)
        #expect(a.count == 43)
        #expect(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

struct AuthSessionTests {
    @Test func startsSignedOutWithoutTokensAndSignedInWithThem() {
        #expect(AuthSession(config: config, store: InMemoryTokenStore()).state == .signedOut)
        let stored = TokenSet(accessToken: "a", refreshToken: "r", idToken: nil, expiresAt: .distantFuture)
        #expect(AuthSession(config: config, store: InMemoryTokenStore(stored)).state == .signedIn)
    }

    @Test func authorizationURLCarriesPKCE() throws {
        let session = AuthSession(config: config, store: InMemoryTokenStore())
        let url = session.beginSignIn()
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.absoluteString.hasPrefix("https://kc/authorize?"))
        #expect(items["client_id"] == "wely-ios-test")
        // Without the audience Auth0 hands out an opaque token the services cannot read.
        #expect(items["audience"] == "wely-api-test")
        #expect(items["screen_hint"] == nil)
        #expect(items["redirect_uri"] == "wely://oauth-callback")
        #expect(items["response_type"] == "code")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"]?.isEmpty == false)
        #expect(items["state"]?.isEmpty == false)
        #expect(items["scope"] == "openid profile email offline_access")
    }

    @Test func completingSignInExchangesTheCode() async throws {
        let http = StubTransport([(200, tokenJSON)])
        let store = InMemoryTokenStore()
        let session = AuthSession(config: config, store: store, http: http)
        let url = session.beginSignIn()
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!

        try await session.completeSignIn(callback: URL(string: "wely://oauth-callback?code=C0DE&state=\(state)")!)

        #expect(session.state == .signedIn)
        #expect(store.load()?.accessToken == "AT")
        let form = http.form(0)
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "C0DE")
        #expect(form["code_verifier"]?.count == 43)
        #expect(try await session.validAccessToken() == "AT")
    }

    @Test func signingInWithAPasswordStoresTheTokens() async throws {
        let http = StubTransport([(200, tokenJSON)])
        let store = InMemoryTokenStore()
        let session = AuthSession(config: config, store: store, http: http)

        try await session.signIn(username: "  robin \n", password: "p&ss=word")

        #expect(session.state == .signedIn)
        #expect(store.load()?.accessToken == "AT")
        #expect(http.requests[0].url?.absoluteString == "https://kc/oauth/token")
        let form = http.form(0)
        #expect(form["grant_type"] == "http://auth0.com/oauth/grant-type/password-realm")
        #expect(form["realm"] == "wely-test-users")
        #expect(form["client_id"] == "wely-ios-test")
        #expect(form["audience"] == "wely-api-test")
        #expect(form["username"] == "robin")
        #expect(form["password"] == "p&ss=word")
        // offline_access, or closing the app for half an hour signs the user out.
        #expect(form["scope"] == "openid profile email offline_access")
    }

    @Test func aWrongPasswordIsInvalidCredentials() async {
        let http = StubTransport([(403, #"{"error":"invalid_grant","error_description":"Wrong email or password."}"#)])
        let session = AuthSession(config: config, store: InMemoryTokenStore(), http: http)
        await #expect(throws: AuthError.invalidCredentials) {
            try await session.signIn(username: "robin", password: "nope")
        }
        #expect(session.state == .signedOut)
    }

    @Test func otherSignInRefusalsKeepAuth0sWords() async {
        let http = StubTransport([(403, #"{"error":"unauthorized_client","error_description":"Grant type 'password' not allowed for the client."}"#), (503, "")])
        let session = AuthSession(config: config, store: InMemoryTokenStore(), http: http)
        await #expect(throws: AuthError.server("Grant type 'password' not allowed for the client.")) {
            try await session.signIn(username: "robin", password: "pw")
        }
        await #expect(throws: AuthError.server("HTTP 503")) {
            try await session.signIn(username: "robin", password: "pw")
        }
    }

    @Test func signUpOpensAuth0sSignUpScreen() {
        let session = AuthSession(config: config, store: InMemoryTokenStore())
        let url = session.beginSignIn(signUp: true)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.absoluteString.hasPrefix("https://kc/authorize?"))
        #expect(items["screen_hint"] == "signup")
        #expect(items["audience"] == "wely-api-test")
        #expect(items["code_challenge"]?.isEmpty == false)
    }

    @Test(arguments: ["google-oauth2", "github"])
    func socialSignInGoesStraightToTheConnection(connection: String) {
        let session = AuthSession(config: config, store: InMemoryTokenStore())
        let url = session.beginSignIn(connection: connection)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.absoluteString.hasPrefix("https://kc/authorize?"))
        #expect(items["connection"] == connection)
        #expect(items["screen_hint"] == nil)
        #expect(items["audience"] == "wely-api-test")
        #expect(items["scope"] == "openid profile email offline_access")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"]?.isEmpty == false)
        #expect(items["state"]?.isEmpty == false)
    }

    @Test func aPlainSignInNamesNoConnection() {
        let session = AuthSession(config: config, store: InMemoryTokenStore())
        let items = URLComponents(url: session.beginSignIn(), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!items.contains { $0.name == "connection" })
    }

    @Test func socialSignInExchangesTheCodeWithTheVerifier() async throws {
        let http = StubTransport([(200, tokenJSON)])
        let session = AuthSession(config: config, store: InMemoryTokenStore(), http: http)
        let items = URLComponents(url: session.beginSignIn(connection: "github"), resolvingAgainstBaseURL: false)!.queryItems!
        let state = items.first { $0.name == "state" }!.value!
        let challenge = items.first { $0.name == "code_challenge" }!.value!

        try await session.completeSignIn(callback: URL(string: "wely://oauth-callback?code=C0DE&state=\(state)")!)

        #expect(session.state == .signedIn)
        let form = http.form(0)
        #expect(form["grant_type"] == "authorization_code")
        #expect(PKCE.challenge(for: form["code_verifier"] ?? "") == challenge)
    }

    @Test func aForeignStateIsRefused() async {
        let session = AuthSession(config: config, store: InMemoryTokenStore(), http: StubTransport([]))
        _ = session.beginSignIn()
        await #expect(throws: AuthError.stateMismatch) {
            try await session.completeSignIn(callback: URL(string: "wely://oauth-callback?code=C&state=other")!)
        }
        #expect(session.state == .signedOut)
    }

    @Test func anAuth0ErrorIsSurfaced() async {
        let session = AuthSession(config: config, store: InMemoryTokenStore(), http: StubTransport([]))
        _ = session.beginSignIn()
        await #expect(throws: AuthError.server("denied")) {
            try await session.completeSignIn(callback: URL(string: "wely://oauth-callback?error=access_denied&error_description=denied")!)
        }
    }

    @Test func aCallbackWithoutPendingSignInIsRefused() async {
        let session = AuthSession(config: config, store: InMemoryTokenStore(), http: StubTransport([]))
        await #expect(throws: AuthError.stateMismatch) {
            try await session.completeSignIn(callback: URL(string: "wely://oauth-callback?code=C&state=s")!)
        }
    }

    @Test func anExpiringTokenIsRefreshed() async throws {
        let expiring = TokenSet(accessToken: "old", refreshToken: "RT0", idToken: nil, expiresAt: .now.addingTimeInterval(5))
        let http = StubTransport([(200, tokenJSON)])
        let session = AuthSession(config: config, store: InMemoryTokenStore(expiring), http: http)

        #expect(try await session.validAccessToken() == "AT")
        #expect(http.form(0)["grant_type"] == "refresh_token")
        #expect(http.form(0)["refresh_token"] == "RT0")
    }

    @Test func aRefreshWithoutANewRefreshTokenKeepsTheOldOne() async throws {
        let expiring = TokenSet(accessToken: "old", refreshToken: "RT0", idToken: nil, expiresAt: .now)
        let store = InMemoryTokenStore(expiring)
        let session = AuthSession(config: config, store: store, http: StubTransport([(200, #"{"access_token":"AT","expires_in":300}"#)]))

        #expect(try await session.validAccessToken() == "AT")
        #expect(store.load()?.refreshToken == "RT0")
    }

    @Test func aRefreshRefusedByAuth0SignsOut() async {
        // Auth0 answers a revoked or reused refresh token with 403 invalid_grant.
        let store = InMemoryTokenStore(TokenSet(accessToken: "old", refreshToken: "RT0", idToken: nil, expiresAt: .now))
        let session = AuthSession(config: config, store: store, http: StubTransport([(403, #"{"error":"invalid_grant","error_description":"Unknown or invalid refresh token."}"#)]))

        await #expect(throws: AuthError.sessionExpired) { try await session.validAccessToken() }
        #expect(session.state == .signedOut)
        #expect(store.load() == nil)
    }

    @Test func aRefusedRefreshSignsOut() async {
        let expiring = TokenSet(accessToken: "old", refreshToken: "RT0", idToken: nil, expiresAt: .now)
        let store = InMemoryTokenStore(expiring)
        let session = AuthSession(config: config, store: store, http: StubTransport([(400, #"{"error":"invalid_grant"}"#)]))

        await #expect(throws: AuthError.sessionExpired) { try await session.validAccessToken() }
        #expect(session.state == .signedOut)
        #expect(session.lastError == .sessionExpired)
        #expect(store.load() == nil)
    }

    @Test func aRefreshWithoutNetworkKeepsTheSession() async {
        let expiring = TokenSet(accessToken: "old", refreshToken: "RT0", idToken: nil, expiresAt: .now)
        let store = InMemoryTokenStore(expiring)
        let session = AuthSession(config: config, store: store, http: StubTransport([(-1, "")]))

        await #expect(throws: URLError.self) { try await session.validAccessToken() }
        #expect(session.state == .signedIn)
        #expect(store.load() == expiring)
    }

    @Test func anAuth0OutageKeepsTheSession() async {
        let expiring = TokenSet(accessToken: "old", refreshToken: "RT0", idToken: nil, expiresAt: .now)
        let session = AuthSession(config: config, store: InMemoryTokenStore(expiring), http: StubTransport([(502, "<html>")]))

        await #expect(throws: AuthError.server("HTTP 502")) { try await session.validAccessToken() }
        #expect(session.state == .signedIn)
        #expect(session.lastError == nil)
    }

    @Test func restorePicksUpASessionSavedSinceLaunch() {
        let store = InMemoryTokenStore()
        let session = AuthSession(config: config, store: store, http: StubTransport([]))
        #expect(session.state == .signedOut)

        store.save(TokenSet(accessToken: "a", refreshToken: "RT", idToken: nil, expiresAt: .distantFuture))
        session.restore()

        #expect(session.state == .signedIn)
    }

    @Test func restoreFindsNothingAfterSigningOut() async {
        let store = InMemoryTokenStore(TokenSet(accessToken: "a", refreshToken: "RT", idToken: nil, expiresAt: .distantFuture))
        let session = AuthSession(config: config, store: store, http: StubTransport([(204, "")]))
        await session.signOut()

        session.restore()

        #expect(session.state == .signedOut)
    }

    @Test func signOutClearsAndRevokesTheRefreshToken() async {
        let tokens = TokenSet(accessToken: "a", refreshToken: "RT", idToken: nil, expiresAt: .distantFuture)
        let http = StubTransport([(204, "")])
        let store = InMemoryTokenStore(tokens)
        let session = AuthSession(config: config, store: store, http: http)

        await session.signOut()

        #expect(session.state == .signedOut)
        #expect(store.load() == nil)
        #expect(http.requests.first?.url?.absoluteString == "https://kc/oauth/revoke")
        #expect(http.form(0)["token"] == "RT")
        #expect(http.form(0)["client_id"] == "wely-ios-test")
    }
}

struct APIClientTests {
    private func signedIn(_ responses: [(Int, String)]) -> (APIClient, AuthSession, StubTransport) {
        let http = StubTransport(responses)
        let tokens = TokenSet(accessToken: "AT0", refreshToken: "RT0", idToken: nil, expiresAt: .distantFuture)
        let session = AuthSession(config: config, store: InMemoryTokenStore(tokens), http: http)
        return (APIClient(session: session, http: http), session, http)
    }

    @Test func sendsTheBearerToken() async throws {
        let (api, _, http) = signedIn([(200, #"{"id":"u","userName":"robin"}"#)])
        let user: UserProfile = try await api.get("user-service/profile")
        #expect(user.userName == "robin")
        #expect(http.requests[0].url?.absoluteString == "http://gw/api/v1/user-service/profile")
        #expect(http.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer AT0")
    }

    @Test func a401RefreshesThenRetries() async throws {
        let (api, _, http) = signedIn([(401, ""), (200, tokenJSON), (200, #"{"id":"u","userName":"robin"}"#)])
        let user: UserProfile = try await api.get("user-service/profile")
        #expect(user.id == "u")
        #expect(http.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer AT")
    }

    @Test func a401AfterRefreshSignsOut() async {
        let (api, session, _) = signedIn([(401, ""), (200, tokenJSON), (401, "")])
        await #expect(throws: APIError.self) { let _: UserProfile = try await api.get("x") }
        #expect(session.state == .signedOut)
    }

    @Test func a401WhileOfflineKeepsTheSession() async {
        let (api, session, _) = signedIn([(401, ""), (-1, "")])
        await #expect(throws: APIError.self) { let _: UserProfile = try await api.get("x") }
        #expect(session.state == .signedIn)
    }

    @Test func businessCodesGiveTheirSentence() async {
        let (api, _, _) = signedIn([(404, #"{"code":"SCL-BUS-014","message":"expired"}"#)])
        do {
            let _: UserProfile = try await api.get("x")
            Issue.record("expected a failure")
        } catch let error as APIError {
            #expect(error.code == "SCL-BUS-014")
            #expect(error.status == 404)
            #expect(error.localizedDescription.hasPrefix("Cette invitation a expiré"))
        } catch { Issue.record("unexpected \(error)") }
    }

    @Test func postsJSONAndQueries() async throws {
        let (api, _, http) = signedIn([(200, #"{"id":"e1","title":"T","organizerId":"u"}"#), (200, "[]")])
        let start = Date(timeIntervalSince1970: 1_792_083_600)
        _ = try await EventService(api: api).create(EventCreateRequest(title: "T", startDate: start, location: "Lyon"))
        let body = try JSONSerialization.jsonObject(with: http.requests[0].httpBody!) as! [String: Any]
        #expect(http.requests[0].httpMethod == "POST")
        #expect(http.requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(body["title"] as? String == "T")
        #expect(body["startDate"] as? String == "2026-10-15T17:00:00Z")

        _ = try await SocialService(api: api).explore(query: "rando")
        #expect(http.requests[1].url?.query() == "q=rando")
    }

    @Test func uploadsMultipart() async throws {
        let (api, _, http) = signedIn([(200, #"{"profilePicUrl":"https://s3/x.jpg"}"#)])
        let url = try await UserService(api: api).uploadPicture(jpeg: Data([0xFF, 0xD8]))
        #expect(url == "https://s3/x.jpg")
        let contentType = http.requests[0].value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: http.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains(#"name="file"; filename="avatar.jpg""#))
    }

    @Test func serverErrorsAndBadBodiesAreTyped() async {
        let (api, _, _) = signedIn([(503, ""), (200, "not json")])
        do {
            let _: UserProfile = try await api.get("x")
            Issue.record("expected a failure")
        } catch {
            #expect(error.localizedDescription == "Le serveur Wely ne répond pas (503).")
        }
        do {
            let _: UserProfile = try await api.get("x")
            Issue.record("expected a failure")
        } catch {
            #expect(error.localizedDescription == "Réponse inattendue du serveur.")
        }
    }

    @Test func liveBackendSkipsUnreadableEvents() async throws {
        let (api, _, http) = signedIn([(200, #"[{"id":"e1","title":"T","organizerId":"u"},{"oops":1}]"#)])
        let events = try await EventService(api: api).subscribed()
        #expect(events.map(\.id) == ["e1"])
        #expect(http.requests[0].url?.path() == "/api/v1/events-service/events/me/subscribed")
    }
}
