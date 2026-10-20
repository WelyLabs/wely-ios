import Foundation
import Testing
@testable import Wely

struct ChatSocketTests {
    /// An APPLICATION_ERROR frame on stream 1, as wely-chat answers a refused `chat.send`.
    private func refused(_ data: String) throws -> RSocketError {
        let raw = Data([0, 0, 0, 1, UInt8(0x0B << 2), 0, 0, 0, 0x02, 0x01] + Array(data.utf8))
        guard case let .error(_, code, message) = try #require(RSocketFrame.decode(raw)) else {
            Issue.record("not an error frame")
            return .closed
        }
        return RSocketError(code: code, data: message)
    }

    @Test func refusal_shouldExplainAJsonProblemByItsCode() throws {
        let error = try refused(#"{"title":"Conversation read-only","status":409,"detail":"The other participant deleted their account: this conversation can be read, not written to.","code":"CHT-BUS-012","requestId":"r1"}"#)
        #expect(error.code == "CHT-BUS-012")
        #expect(ChatSocket.refusal(of: error) == ErrorMessages.text(for: "CHT-BUS-012"))
        #expect(error.localizedDescription == ErrorMessages.text(for: "CHT-BUS-012"))
    }

    @Test func refusal_shouldStayNil_whenThePlainTextErrorHasNoCode() throws {
        let error = try refused("This account has been deleted.")
        #expect(error.code == nil)
        #expect(ChatSocket.refusal(of: error) == nil)
        // As before the problem format: the plain text is what the error says.
        #expect(error.localizedDescription == "This account has been deleted.")
    }

    @Test func refusal_shouldStayNil_forACodeWithoutASentence() throws {
        let error = try refused(#"{"detail":"Mongo is down","code":"CHT-TEC-001","status":502}"#)
        #expect(ChatSocket.refusal(of: error) == nil)
        #expect(error.localizedDescription == "Le message n'a pas pu être envoyé.")
    }

    @Test func refusal_shouldStayNil_forTransportFailures() {
        #expect(ChatSocket.refusal(of: RSocketError.notConnected) == nil)
        #expect(ChatSocket.refusal(of: URLError(.notConnectedToInternet)) == nil)
    }
}
