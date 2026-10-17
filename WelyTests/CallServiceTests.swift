import Foundation
import Testing
@testable import Wely

struct CallServiceTests {
    private static let call = #"{"id":"c1","conversationId":"conv1","startedBy":"u1","media":"AUDIO","status":"RINGING","memberIds":["u1","u2"],"participants":[]}"#

    private func service(_ http: StubTransport) -> CallService {
        let session = AuthSession(store: InMemoryTokenStore(TokenSet(accessToken: "t", refreshToken: nil, idToken: nil, expiresAt: .distantFuture)))
        return CallService(api: APIClient(session: session, http: http))
    }

    @Test func startPostsTheConversationAndMedia() async throws {
        let http = StubTransport([(200, Self.call)])
        let call = try await service(http).start(conversationId: "conv1", media: .video)
        #expect(call.id == "c1")
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path().hasSuffix("chat-service/calls") == true)
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body == ["conversationId": "conv1", "media": "VIDEO"])
    }

    @Test func liveIsNilWhenNoCallGoesOn() async throws {
        let call = try await service(StubTransport([(204, "")])).live(conversationId: "conv1")
        #expect(call == nil)
    }

    @Test func liveAnswersTheConversationsCall() async throws {
        let call = try await service(StubTransport([(200, Self.call)])).live(conversationId: "conv1")
        #expect(call?.status == .ringing)
    }

    @Test func aFullCallFailsWithItsCode() async {
        let http = StubTransport([(409, #"{"code":"CHT-BUS-009","message":"full"}"#)])
        await #expect(throws: APIError.self) { try await service(http).join("c1") }
    }

    @Test func eachStepTargetsItsCall() async throws {
        let http = StubTransport([(204, ""), (204, ""), (204, ""), (204, "")])
        let calls = service(http)
        try await calls.heartbeat("c1")
        try await calls.leave("c1")
        try await calls.decline("c1")
        try await calls.unsubscribe("c1", mids: ["3"])
        #expect(http.requests.map { $0.url!.lastPathComponent } == ["heartbeat", "leave", "decline", "unsubscribe"])
    }
}
