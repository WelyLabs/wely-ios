import Foundation

enum APIError: LocalizedError {
    case unauthorized
    /// `code` is the backend's business code (`SCL-BUS-013`...), when it sent one.
    case http(status: Int, code: String? = nil, message: String? = nil)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Votre session a expiré, reconnectez-vous."
        case .http(_, let code?, _) where ErrorMessages.text(for: code) != nil: ErrorMessages.text(for: code)
        case .http(let status, _, _) where status >= 500: "Le serveur Wely ne répond pas (\(status))."
        case .http(403, _, _): "Vous n'avez pas accès à cette ressource."
        case .http(404, _, _): "Introuvable : cet élément n'existe pas ou n'est plus visible."
        case .http(let status, _, _): "La requête a échoué (\(status))."
        case .decoding: "Réponse inattendue du serveur."
        case .network: "Impossible de joindre Wely. Vérifiez votre connexion."
        }
    }

    var code: String? {
        if case .http(_, let code, _) = self { return code }
        return nil
    }

    var status: Int? {
        if case .http(let status, _, _) = self { return status }
        return nil
    }
}

/// A file sent as `multipart/form-data`, as the web app's `FormData`.
struct UploadFile {
    var field = "file"
    var fileName = "photo.jpg"
    var mimeType = "image/jpeg"
    let data: Data
}

/// Calls the gateway with the session's bearer token; on a 401, refreshes once and retries.
final class APIClient {
    let session: AuthSession
    private let http: HTTPTransport
    private let baseURL: URL
    private let decoder = JSONDecoder.wely
    private let encoder = JSONEncoder.wely

    init(session: AuthSession, http: HTTPTransport = URLSession.shared) {
        self.session = session
        self.http = http
        self.baseURL = session.config.apiURL
    }

    // MARK: Verbs

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await decode(send(request("GET", path, query: query)))
    }

    /// For endpoints that answer 204 when there is nothing: nil then.
    func getIfPresent<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T? {
        let data = try await send(request("GET", path, query: query))
        return data.isEmpty ? nil : try decode(data) as T
    }

    func post<T: Decodable>(_ path: String, body: some Encodable = Empty()) async throws -> T {
        try await decode(send(request("POST", path, body: body)))
    }

    func put<T: Decodable>(_ path: String, body: some Encodable = Empty()) async throws -> T {
        try await decode(send(request("PUT", path, body: body)))
    }

    /// For the many endpoints that answer 204 or a body the caller does not need.
    func send(_ method: String, _ path: String, body: some Encodable = Empty(), query: [String: String?] = [:]) async throws {
        _ = try await send(request(method, path, query: query, body: method == "GET" || method == "DELETE" ? nil : body))
    }

    func delete(_ path: String, query: [String: String?] = [:]) async throws {
        _ = try await send(request("DELETE", path, query: query))
    }

    func upload<T: Decodable>(_ path: String, method: String = "POST", file: UploadFile, fields: [String: String] = [:]) async throws -> T {
        let boundary = "wely-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.fileName)\"\r\n")
        body.append("Content-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        body.append("\r\n--\(boundary)--\r\n")

        var request = request(method, path)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await decode(send(request))
    }

    // MARK: Plumbing

    func url(_ path: String, query: [String: String?] = [:]) -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        return components.url!
    }

    private func request(_ method: String, _ path: String, query: [String: String?] = [:], body: (any Encodable)? = nil) -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body, !(body is Empty) {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? encoder.encode(body)
        }
        return request
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == Empty.self { return Empty() as! T }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func send(_ request: URLRequest, retried: Bool = false) async throws -> Data {
        var request = request
        let token: String
        do {
            token = try await session.validAccessToken()
        } catch {
            throw APIError.unauthorized
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        if response.statusCode == 401 {
            guard !retried, (try? await session.refresh()) != nil else {
                session.expire()
                throw APIError.unauthorized
            }
            return try await send(request, retried: true)
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError.http(status: response.statusCode, code: body?.code, message: body?.message)
        }
        return data
    }
}

/// No body, or a body nobody reads.
struct Empty: Codable {}

private struct ErrorBody: Decodable {
    let code: String?
    let message: String?
}

private extension Data {
    mutating func append(_ string: String) { append(Data(string.utf8)) }
}

extension JSONEncoder {
    /// Dates as ISO-8601 instants, as Angular serialises a `Date`.
    static var wely: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
