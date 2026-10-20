import Foundation
import Testing
@testable import Wely

struct RSocketProblemTests {
    @Test func payload_shouldReadAJsonProblem() {
        let payload = #"{"type":"about:blank","title":"Conversation read-only","status":409,"detail":"The other participant deleted their account.","code":"CHT-BUS-012","timestamp":"2026-10-20T10:00:00Z","requestId":"req-42"}"#
        #expect(RSocketProblem(payload: payload) == RSocketProblem(
            code: "CHT-BUS-012", detail: "The other participant deleted their account.", status: 409, requestId: "req-42"))
    }

    @Test func payload_shouldKeepPlainTextAsTheDetail_whenTheBackendSendsNoJson() {
        let problem = RSocketProblem(payload: "This account has been deleted.")
        #expect(problem == RSocketProblem(detail: "This account has been deleted."))
        #expect(problem.code == nil)
    }

    @Test func payload_shouldKeepMalformedJsonWhole() {
        let payload = #"{"code":"CHT-BUS-012","detail":"#
        #expect(RSocketProblem(payload: payload) == RSocketProblem(detail: payload))
    }

    @Test(arguments: [#"["CHT-BUS-012"]"#, #""CHT-BUS-012""#, "409", "null", #"{"message":"no problem fields"}"#])
    func payload_shouldKeepJsonThatIsNotAProblemObjectWhole(payload: String) {
        #expect(RSocketProblem(payload: payload) == RSocketProblem(detail: payload))
    }

    @Test func payload_shouldTolerateMissingAndMistypedFields() {
        let problem = RSocketProblem(payload: #" {"title":"Call full","status":"409","code":"CHT-BUS-009"}"#)
        #expect(problem == RSocketProblem(code: "CHT-BUS-009", detail: "Call full"))
    }

    @Test func payload_shouldReadAnEmptyPayloadAsAnEmptyDetail() {
        #expect(RSocketProblem(payload: "") == RSocketProblem(detail: ""))
    }
}
