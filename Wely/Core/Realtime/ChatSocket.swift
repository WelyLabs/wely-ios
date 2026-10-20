import Foundation
import Observation

/// The chat's live side: one RSocket connection to the gateway, `chat.stream` fanned out to
/// every open screen, `call.events` to the calls, `chat.send` to post. Reconnects with backoff, as wely-web does.
@Observable
final class ChatSocket {
    private(set) var isConnected = false

    @ObservationIgnored private let session: AuthSession
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private var connection: RSocketConnection?
    @ObservationIgnored private var connecting: Task<Void, Error>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var callTask: Task<Void, Never>?
    @ObservationIgnored private var callListeners: [UUID: AsyncStream<CallEvent>.Continuation] = [:]
    @ObservationIgnored private var listeners: [UUID: AsyncStream<Message>.Continuation] = [:]
    @ObservationIgnored private var attempt = 0

    init(session: AuthSession, enabled: Bool = true) {
        self.session = session
        self.url = session.config.rsocketURL
        self.enabled = enabled
    }

    /// Every message pushed by the server for the user, from now on.
    func messages() -> AsyncStream<Message> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Message>.makeStream()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.listeners.removeValue(forKey: id) }
        }
        Task { try? await ensureConnected() }
        return stream
    }

    /// Every call event for the user (ringing, joined, left, ended...), from now on.
    func callEvents() -> AsyncStream<CallEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<CallEvent>.makeStream()
        callListeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.callListeners.removeValue(forKey: id) }
        }
        Task { try? await ensureConnected() }
        return stream
    }

    /// Sends a text message; answers the stored message.
    func send(_ input: ChatInput) async throws -> Message? {
        guard enabled else { throw RSocketError.notConnected }
        try await ensureConnected()
        guard let connection else { throw RSocketError.notConnected }
        let token = try await session.validAccessToken()
        let data = try await connection.requestResponse(
            metadata: RSocketMetadata.compose(route: "chat.send", bearer: token),
            data: try JSONEncoder.wely.encode(input)
        )
        return data.flatMap { try? JSONDecoder.wely.decode(Message.self, from: $0) }
    }

    /// Why `send` failed, worth an alert: the sentence for a refusal wely-chat gave a known code.
    /// Nil otherwise (no code, unknown code, transport failure): the failed message's retry says enough.
    static func refusal(of error: Error) -> String? {
        guard let code = (error as? RSocketError)?.code else { return nil }
        return ErrorMessages.text(for: code)
    }

    func disconnect() {
        streamTask?.cancel()
        callTask?.cancel()
        connection?.close()
        connection = nil
        isConnected = false
    }

    private func ensureConnected() async throws {
        guard enabled, session.state == .signedIn else { throw RSocketError.notConnected }
        if connection?.isOpen == true { return }
        if let connecting { return try await connecting.value }
        let task = Task { try await connect() }
        connecting = task
        defer { connecting = nil }
        try await task.value
    }

    private func connect() async throws {
        let connection = RSocketConnection(url: url)
        connection.onClose = { [weak self] in self?.connectionLost() }
        try await connection.connect()
        self.connection = connection
        isConnected = true
        attempt = 0
        let token = try await session.validAccessToken()
        let stream = connection.requestStream(metadata: RSocketMetadata.compose(route: "chat.stream", bearer: token))
        streamTask = Task {
            do {
                for try await data in stream {
                    guard let message = try? JSONDecoder.wely.decode(Message.self, from: data) else { continue }
                    listeners.values.forEach { $0.yield(message) }
                }
            } catch {}
        }
        let calls = connection.requestStream(metadata: RSocketMetadata.compose(route: "call.events", bearer: token))
        callTask = Task {
            do {
                for try await data in calls {
                    guard let event = try? JSONDecoder.wely.decode(CallEvent.self, from: data) else { continue }
                    callListeners.values.forEach { $0.yield(event) }
                }
            } catch {}
        }
    }

    private func connectionLost() {
        isConnected = false
        connection = nil
        streamTask?.cancel()
        callTask?.cancel()
        guard session.state == .signedIn, !listeners.isEmpty || !callListeners.isEmpty else { return }
        let delay = min(30, pow(2, Double(attempt)))
        attempt += 1
        Task {
            try? await Task.sleep(for: .seconds(delay))
            try? await ensureConnected()
        }
    }
}
