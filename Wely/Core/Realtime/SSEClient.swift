import Foundation

/// One server-sent event.
struct SSEMessage: Equatable, Sendable {
    var event = "message"
    var data = ""
}

/// Parses the `text/event-stream` format line by line.
struct SSEParser {
    private var current = SSEMessage()
    private var dataLines: [String] = []

    /// Feeds one line; returns the event a blank line completes.
    mutating func feed(_ line: String) -> SSEMessage? {
        if line.isEmpty {
            defer { current = SSEMessage(); dataLines = [] }
            guard !dataLines.isEmpty else { return nil }
            current.data = dataLines.joined(separator: "\n")
            return current
        }
        if line.hasPrefix(":") { return nil }
        let (field, value) = Self.split(line)
        switch field {
        case "event": current.event = value
        case "data": dataLines.append(value)
        default: break
        }
        return nil
    }

    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (String(line[..<colon]), String(value))
    }
}

/// Server-sent events read with a bearer token, reconnecting with backoff until cancelled.
///
/// `finalStatuses` end the stream instead of retrying (a 403 will not fix itself).
enum SSEClient {
    static func stream(
        url: URL,
        session: AuthSession,
        finalStatuses: Set<Int> = [403, 404],
        onOpen: (@MainActor () -> Void)? = nil
    ) -> AsyncStream<SSEMessage> {
        AsyncStream { continuation in
            let task = Task {
                var attempt = 0
                while !Task.isCancelled {
                    do {
                        let token = try await session.validAccessToken()
                        var request = URLRequest(url: url, timeoutInterval: 3600)
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if finalStatuses.contains(status) { break }
                        guard status == 200 else { throw URLError(.badServerResponse) }
                        attempt = 0
                        onOpen?()
                        // Split by hand: `bytes.lines` drops the blank lines that end an event.
                        var parser = SSEParser()
                        var line: [UInt8] = []
                        for try await byte in bytes {
                            guard byte == 0x0A else { line.append(byte); continue }
                            if line.last == 0x0D { line.removeLast() }
                            if let message = parser.feed(String(decoding: line, as: UTF8.self)) { continuation.yield(message) }
                            line.removeAll(keepingCapacity: true)
                        }
                    } catch is CancellationError {
                        break
                    } catch AuthError.sessionExpired {
                        break
                    } catch {}
                    if Task.isCancelled { break }
                    let delay = min(30, pow(2, Double(attempt)))
                    attempt += 1
                    try? await Task.sleep(for: .seconds(delay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
