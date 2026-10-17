import Foundation

/// `chat-service/calls`: wely-chat decides who may call and holds the relay's secret, so every
/// step of a call goes through it.
struct CallService {
    let api: APIClient
    private let base = "chat-service/calls"

    /// Calls a conversation's members, or answers the call already going on there.
    func start(conversationId: String, media: CallMedia) async throws -> Call {
        try await api.post(base, body: StartCallRequest(conversationId: conversationId, media: media))
    }
    /// The conversation's live call, nil when there is none.
    func live(conversationId: String) async throws -> Call? {
        try await api.getIfPresent("\(base)/live", query: ["conversationId": conversationId])
    }
    func join(_ callId: String) async throws -> CallJoin { try await api.post("\(base)/\(callId)/join") }
    func publish(_ callId: String, offer: SessionDescription, tracks: [PublishedTrack]) async throws -> SessionDescription {
        try await api.post("\(base)/\(callId)/publish", body: PublishRequest(offer: offer, tracks: tracks))
    }
    func subscribe(_ callId: String, tracks: [TrackRequest]) async throws -> CallSubscription {
        try await api.post("\(base)/\(callId)/subscribe", body: SubscribeRequest(tracks: tracks))
    }
    func renegotiate(_ callId: String, answer: SessionDescription) async throws {
        try await api.send("PUT", "\(base)/\(callId)/renegotiate", body: answer)
    }
    func chooseLayers(_ callId: String, _ choices: [LayerChoice]) async throws {
        try await api.send("PUT", "\(base)/\(callId)/layers", body: LayersRequest(choices: choices))
    }
    func unsubscribe(_ callId: String, mids: [String]) async throws {
        try await api.send("POST", "\(base)/\(callId)/unsubscribe", body: UnsubscribeRequest(mids: mids))
    }
    func heartbeat(_ callId: String) async throws { try await api.send("POST", "\(base)/\(callId)/heartbeat") }
    func leave(_ callId: String) async throws { try await api.send("POST", "\(base)/\(callId)/leave") }
    func decline(_ callId: String) async throws { try await api.send("POST", "\(base)/\(callId)/decline") }
}
