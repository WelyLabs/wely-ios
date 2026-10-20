import Foundation

/// Why wely-chat refused an RSocket request: the data of its APPLICATION_ERROR frame.
///
/// wely-chat sends the same problem as its REST errors, as JSON
/// (`{"type","title","status","detail","code","timestamp","requestId"}`); an older backend sends
/// only the detail, as plain text. Both read the same here, the plain text as `detail` and no code.
nonisolated struct RSocketProblem: Equatable, Sendable {
    /// The business code (`CHT-BUS-012`...) a client branches on, when the backend sent one.
    let code: String?
    /// For developers and logs, in English; the user-facing wording comes from `ErrorMessages`.
    let detail: String
    let status: Int?
    let requestId: String?

    init(code: String? = nil, detail: String, status: Int? = nil, requestId: String? = nil) {
        self.code = code
        self.detail = detail
        self.status = status
        self.requestId = requestId
    }

    /// Reads an error frame's data: a JSON object carrying a `code` or a `detail` is a problem;
    /// anything else (plain text, malformed JSON, an array, a bare string) is kept whole as the detail.
    init(payload: String) {
        guard let object = Self.problemObject(in: payload) else {
            self.init(detail: payload)
            return
        }
        self.init(
            code: object["code"] as? String,
            detail: object["detail"] as? String ?? object["title"] as? String ?? "",
            status: object["status"] as? Int,
            requestId: object["requestId"] as? String
        )
    }

    private static func problemObject(in payload: String) -> [String: Any]? {
        guard payload.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
              let object = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
              object["code"] is String || object["detail"] is String
        else { return nil }
        return object
    }
}
