import Foundation
import Testing
@testable import Wely

private let config = AppConfig(gatewayURL: URL(string: "http://gw")!, keycloakURL: URL(string: "http://kc")!, webURL: URL(string: "http://web")!)

struct PreferencesModelsTests {
    @Test func themesReadAndWriteAsWelyUsersSpellsThem() throws {
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: Data(#"{"theme":"DARK"}"#.utf8))
        #expect(decoded.theme == .dark)
        #expect(decoded.theme.colorScheme == .dark)
        #expect(String(data: try JSONEncoder().encode(UserPreferences(theme: .light)), encoding: .utf8) == #"{"theme":"LIGHT"}"#)
    }

    @Test func anUnknownThemeReadsAsSystem() throws {
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: Data(#"{"theme":"SEPIA"}"#.utf8))
        #expect(decoded.theme == .system)
        #expect(decoded.theme.colorScheme == nil)
    }

    @Test func deletionRefusalsHaveTheirOutcome() {
        #expect(AccountDeletionOutcome(refusal: APIError.http(status: 410, code: "USR-BUS-012")) == .deleted)
        #expect(AccountDeletionOutcome(refusal: APIError.http(status: 403, code: "USR-BUS-011")) == .protected)
        #expect(AccountDeletionOutcome(refusal: APIError.http(status: 403, code: "USR-BUS-014")) == .unavailable)
        #expect(AccountDeletionOutcome(refusal: APIError.http(status: 403, code: "USR-BUS-010")) == .reauthenticationRequired)
        if case .failed = AccountDeletionOutcome(refusal: APIError.http(status: 500)) {} else { Issue.record("a 500 is a failure") }
    }
}

@MainActor
struct PreferencesServiceTests {
    private func signedIn(_ responses: [(Int, String)]) -> (AppModel, StubTransport) {
        let http = StubTransport(responses)
        let stored = TokenSet(accessToken: "AT", refreshToken: "RT", idToken: nil, expiresAt: .distantFuture)
        let session = AuthSession(config: config, store: InMemoryTokenStore(stored), http: http)
        return (AppModel(session: session, http: http), http)
    }

    @Test func choosingAThemeSavesItWithTheAccount() async throws {
        let (app, http) = signedIn([(200, #"{"theme":"DARK"}"#)])
        try await app.chooseTheme(.dark)
        #expect(app.theme == .dark)
        #expect(http.requests[0].httpMethod == "PUT")
        #expect(http.requests[0].url?.path() == "/api/v1/user-service/profile/preferences")
        #expect(String(data: http.requests[0].httpBody ?? Data(), encoding: .utf8) == #"{"theme":"DARK"}"#)
    }

    @Test func aRefusedThemePutsThePreviousOneBack() async {
        let (app, _) = signedIn([(500, "")])
        app.theme = .light
        await #expect(throws: APIError.self) { try await app.chooseTheme(.dark) }
        #expect(app.theme == .light)
    }

    @Test func deletingTheAccountCallsWelyUsers() async throws {
        let (app, http) = signedIn([(200, #"{"allowed":true}"#), (202, "")])
        #expect(try await app.users.deletionEligibility().allowed)
        try await app.users.deleteAccount()
        #expect(http.requests[1].httpMethod == "DELETE")
        #expect(http.requests[1].url?.path() == "/api/v1/user-service/profile")
    }
}
