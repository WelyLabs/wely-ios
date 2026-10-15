import Foundation

/// The RSocket frames this client speaks (spec 1.0), over WebSocket: one frame per binary
/// message, no length prefix — what wely-chat's Spring RSocket endpoint expects.
enum RSocketFrame: Equatable {
    case setup(keepAliveMs: UInt32, lifetimeMs: UInt32, metadataMime: String, dataMime: String)
    case keepAlive(respond: Bool, position: UInt64 = 0)
    case requestResponse(stream: UInt32, metadata: Data, data: Data)
    case requestStream(stream: UInt32, initialN: UInt32, metadata: Data, data: Data)
    case requestN(stream: UInt32, n: UInt32)
    case cancel(stream: UInt32)
    case payload(stream: UInt32, data: Data?, next: Bool, complete: Bool)
    case error(stream: UInt32, code: UInt32, message: String)
    case other(stream: UInt32, type: UInt8)

    enum FrameType: UInt8 {
        case setup = 0x01, keepAlive = 0x03, requestResponse = 0x04, requestStream = 0x06,
             requestN = 0x08, cancel = 0x09, payload = 0x0A, error = 0x0B
    }

    static let metadataFlag: UInt16 = 0x100
    static let followsFlag: UInt16 = 0x80
    static let respondFlag: UInt16 = 0x80
    static let completeFlag: UInt16 = 0x40
    static let nextFlag: UInt16 = 0x20

    // MARK: Encoding

    func encoded() -> Data {
        var out = Data()
        switch self {
        case let .setup(keepAlive, lifetime, metadataMime, dataMime):
            out.header(stream: 0, type: .setup, flags: 0)
            out.uint16(1); out.uint16(0)
            out.uint32(keepAlive); out.uint32(lifetime)
            out.append(UInt8(metadataMime.utf8.count)); out.append(Data(metadataMime.utf8))
            out.append(UInt8(dataMime.utf8.count)); out.append(Data(dataMime.utf8))
        case let .keepAlive(respond, position):
            out.header(stream: 0, type: .keepAlive, flags: respond ? Self.respondFlag : 0)
            out.uint64(position)
        case let .requestResponse(stream, metadata, data):
            out.header(stream: stream, type: .requestResponse, flags: Self.metadataFlag)
            out.metadata(metadata); out.append(data)
        case let .requestStream(stream, n, metadata, data):
            out.header(stream: stream, type: .requestStream, flags: Self.metadataFlag)
            out.uint32(n)
            out.metadata(metadata); out.append(data)
        case let .requestN(stream, n):
            out.header(stream: stream, type: .requestN, flags: 0)
            out.uint32(n)
        case let .cancel(stream):
            out.header(stream: stream, type: .cancel, flags: 0)
        case let .payload(stream, data, next, complete):
            out.header(stream: stream, type: .payload, flags: (next ? Self.nextFlag : 0) | (complete ? Self.completeFlag : 0))
            if let data { out.append(data) }
        case let .error(stream, code, message):
            out.header(stream: stream, type: .error, flags: 0)
            out.uint32(code); out.append(Data(message.utf8))
        case let .other(stream, type):
            out.uint32(stream); out.uint16(UInt16(type) << 10)
        }
        return out
    }

    // MARK: Decoding

    /// Reads a frame; nil when too short to be one.
    static func decode(_ data: Data) -> RSocketFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        let stream = bytes.uint32(at: 0) & 0x7FFF_FFFF
        let typeAndFlags = bytes.uint16(at: 4)
        let rawType = UInt8(typeAndFlags >> 10)
        let flags = typeAndFlags & 0x3FF
        var cursor = 6

        switch FrameType(rawValue: rawType) {
        case .keepAlive:
            let position = bytes.count >= 14 ? bytes.uint64(at: 6) : 0
            return .keepAlive(respond: flags & respondFlag != 0, position: position)
        case .payload:
            if flags & metadataFlag != 0, bytes.count >= cursor + 3 {
                cursor += 3 + Int(bytes.uint24(at: cursor))
            }
            let body = cursor < bytes.count ? Data(bytes[cursor...]) : Data()
            let next = flags & nextFlag != 0
            return .payload(stream: stream, data: next ? body : nil, next: next, complete: flags & completeFlag != 0)
        case .error:
            guard bytes.count >= 10 else { return nil }
            let code = bytes.uint32(at: 6)
            let message = String(decoding: bytes[10...], as: UTF8.self)
            return .error(stream: stream, code: code, message: message)
        case .requestN:
            guard bytes.count >= 10 else { return nil }
            return .requestN(stream: stream, n: bytes.uint32(at: 6))
        case .cancel:
            return .cancel(stream: stream)
        default:
            return .other(stream: stream, type: rawType)
        }
    }
}

/// Composite metadata (`message/x.rsocket.composite-metadata.v0`): the route and the bearer token.
enum RSocketMetadata {
    static let compositeMime = "message/x.rsocket.composite-metadata.v0"
    private static let routingId: UInt8 = 0x7E        // message/x.rsocket.routing.v0
    private static let authenticationId: UInt8 = 0x7C // message/x.rsocket.authentication.v0
    private static let bearerAuthType: UInt8 = 0x81   // well-known « bearer »

    static func compose(route: String, bearer token: String) -> Data {
        var routing = Data([UInt8(route.utf8.count)])
        routing.append(Data(route.utf8))
        var auth = Data([bearerAuthType])
        auth.append(Data(token.utf8))

        var out = Data()
        for (id, content) in [(routingId, routing), (authenticationId, auth)] {
            out.append(0x80 | id)
            out.uint24(UInt32(content.count))
            out.append(content)
        }
        return out
    }
}

private extension Data {
    mutating func uint16(_ value: UInt16) { append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)]) }
    mutating func uint24(_ value: UInt32) { append(contentsOf: [UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]) }
    mutating func uint32(_ value: UInt32) { uint16(UInt16(value >> 16)); uint16(UInt16(value & 0xFFFF)) }
    mutating func uint64(_ value: UInt64) { uint32(UInt32(value >> 32)); uint32(UInt32(value & 0xFFFF_FFFF)) }

    mutating func header(stream: UInt32, type: RSocketFrame.FrameType, flags: UInt16) {
        uint32(stream & 0x7FFF_FFFF)
        uint16(UInt16(type.rawValue) << 10 | (flags & 0x3FF))
    }

    mutating func metadata(_ metadata: Data) {
        uint24(UInt32(metadata.count))
        append(metadata)
    }
}

private extension Array where Element == UInt8 {
    func uint16(at i: Int) -> UInt16 { UInt16(self[i]) << 8 | UInt16(self[i + 1]) }
    func uint24(at i: Int) -> UInt32 { UInt32(self[i]) << 16 | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) }
    func uint32(at i: Int) -> UInt32 { UInt32(uint16(at: i)) << 16 | UInt32(uint16(at: i + 2)) }
    func uint64(at i: Int) -> UInt64 { UInt64(uint32(at: i)) << 32 | UInt64(uint32(at: i + 4)) }
}

enum RSocketError: LocalizedError {
    case notConnected
    case closed
    case server(code: UInt32, message: String)

    var errorDescription: String? {
        switch self {
        case .notConnected, .closed: "La messagerie n'est pas connectée."
        case .server(_, let message): message.isEmpty ? "Le message n'a pas pu être envoyé." : message
        }
    }
}

/// One RSocket connection over a WebSocket: request/response and request/stream, keep-alive.
final class RSocketConnection {
    private let url: URL
    private var socket: URLSessionWebSocketTask?
    private var nextStreamId: UInt32 = 1
    private var responses: [UInt32: CheckedContinuation<Data?, Error>] = [:]
    private var streams: [UInt32: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    private var readTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    /// Called once when the connection drops, so the owner can reconnect.
    var onClose: (() -> Void)?

    static let keepAliveMs: UInt32 = 30_000
    static let lifetimeMs: UInt32 = 90_000

    init(url: URL) { self.url = url }

    var isOpen: Bool { socket != nil }

    func connect() async throws {
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        self.socket = socket
        try await socket.send(.data(RSocketFrame.setup(
            keepAliveMs: Self.keepAliveMs, lifetimeMs: Self.lifetimeMs,
            metadataMime: RSocketMetadata.compositeMime, dataMime: "application/json"
        ).encoded()))
        readTask = Task { await self.readLoop() }
        keepAliveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(Self.keepAliveMs)))
                guard !Task.isCancelled else { return }
                try? await self.socket?.send(.data(RSocketFrame.keepAlive(respond: true).encoded()))
            }
        }
    }

    func close() {
        guard socket != nil else { return }
        socket?.cancel(with: .normalClosure, reason: nil)
        tearDown(RSocketError.closed, notify: false)
    }

    func requestResponse(metadata: Data, data: Data) async throws -> Data? {
        guard let socket else { throw RSocketError.notConnected }
        let id = takeStreamId()
        return try await withCheckedThrowingContinuation { continuation in
            responses[id] = continuation
            Task {
                do {
                    try await socket.send(.data(RSocketFrame.requestResponse(stream: id, metadata: metadata, data: data).encoded()))
                } catch {
                    self.responses.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }

    func requestStream(metadata: Data, data: Data = Data()) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            guard let socket else { continuation.finish(throwing: RSocketError.notConnected); return }
            let id = takeStreamId()
            streams[id] = continuation
            continuation.onTermination = { [weak self] reason in
                guard case .cancelled = reason else { return }
                Task { @MainActor in
                    guard let self, self.streams.removeValue(forKey: id) != nil else { return }
                    try? await self.socket?.send(.data(RSocketFrame.cancel(stream: id).encoded()))
                }
            }
            Task {
                do {
                    try await socket.send(.data(RSocketFrame.requestStream(stream: id, initialN: UInt32(Int32.max), metadata: metadata, data: data).encoded()))
                } catch {
                    self.streams.removeValue(forKey: id)?.finish(throwing: error)
                }
            }
        }
    }

    private func takeStreamId() -> UInt32 {
        // Client streams are odd.
        defer { nextStreamId += 2 }
        return nextStreamId
    }

    private func readLoop() async {
        while let socket {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .data(let bytes): data = bytes
                case .string(let text): data = Data(text.utf8)
                @unknown default: continue
                }
                if let frame = RSocketFrame.decode(data) { await handle(frame) }
            } catch {
                tearDown(error, notify: true)
                return
            }
        }
    }

    private func handle(_ frame: RSocketFrame) async {
        switch frame {
        case let .keepAlive(respond, position) where respond:
            try? await socket?.send(.data(RSocketFrame.keepAlive(respond: false, position: position).encoded()))
        case let .payload(stream, data, next, complete):
            if let continuation = responses.removeValue(forKey: stream) {
                continuation.resume(returning: next ? data : nil)
            } else if let continuation = streams[stream] {
                if next, let data { continuation.yield(data) }
                if complete {
                    streams.removeValue(forKey: stream)
                    continuation.finish()
                }
            }
        case let .error(stream, code, message):
            let error = RSocketError.server(code: code, message: message)
            if stream == 0 {
                tearDown(error, notify: true)
            } else if let continuation = responses.removeValue(forKey: stream) {
                continuation.resume(throwing: error)
            } else {
                streams.removeValue(forKey: stream)?.finish(throwing: error)
            }
        default:
            break
        }
    }

    private func tearDown(_ error: Error, notify: Bool) {
        socket = nil
        keepAliveTask?.cancel()
        readTask?.cancel()
        responses.values.forEach { $0.resume(throwing: error) }
        streams.values.forEach { $0.finish(throwing: error) }
        responses.removeAll()
        streams.removeAll()
        if notify { onClose?() }
    }
}
