import Foundation
import Testing
@testable import Wely

/// Answers every request with the next canned response and records what was sent.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = responses.isEmpty ? (500, "") : responses.removeFirst()
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
private let config = AppConfig(gatewayURL: URL(string: "http://gw")!, keycloakURL: URL(string: "http://kc")!, webURL: URL(string: "http://web")!)

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
        #expect(url.absoluteString.hasPrefix("http://kc/realms/wely-realm/protocol/openid-connect/auth?"))
        #expect(items["client_id"] == "wely-client")
        #expect(items["redirect_uri"] == "wely://oauth-callback")
        #expect(items["response_type"] == "code")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"]?.isEmpty == false)
        #expect(items["state"]?.isEmpty == false)
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

    @Test func aForeignStateIsRefused() async {
        let session = AuthSession(config: config, store: InMemoryTokenStore(), http: StubTransport([]))
        _ = session.beginSignIn()
        await #expect(throws: AuthError.stateMismatch) {
            try await session.completeSignIn(callback: URL(string: "wely://oauth-callback?code=C&state=other")!)
        }
        #expect(session.state == .signedOut)
    }

    @Test func aKeycloakErrorIsSurfaced() async {
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

    @Test func aRefusedRefreshSignsOut() async {
        let expiring = TokenSet(accessToken: "old", refreshToken: "RT0", idToken: nil, expiresAt: .now)
        let store = InMemoryTokenStore(expiring)
        let session = AuthSession(config: config, store: store, http: StubTransport([(400, #"{"error":"invalid_grant"}"#)]))

        await #expect(throws: AuthError.sessionExpired) { try await session.validAccessToken() }
        #expect(session.state == .signedOut)
        #expect(session.lastError == .sessionExpired)
        #expect(store.load() == nil)
    }

    @Test func signOutClearsAndCallsKeycloak() async {
        let tokens = TokenSet(accessToken: "a", refreshToken: "RT", idToken: nil, expiresAt: .distantFuture)
        let http = StubTransport([(204, "")])
        let store = InMemoryTokenStore(tokens)
        let session = AuthSession(config: config, store: store, http: http)

        await session.signOut()

        #expect(session.state == .signedOut)
        #expect(store.load() == nil)
        #expect(http.requests.first?.url?.absoluteString == "http://kc/realms/wely-realm/protocol/openid-connect/logout")
        #expect(http.form(0)["refresh_token"] == "RT")
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
