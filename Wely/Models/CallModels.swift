import Foundation

/// Audio and video calls, as wely-chat describes them (`/chat-service/calls`).
enum CallMedia: String, Codable, Sendable {
    case audio = "AUDIO"
    case video = "VIDEO"
}

enum CallStatus: String, Codable, Sendable {
    case ringing = "RINGING", active = "ACTIVE", ended = "ENDED", missed = "MISSED", declined = "DECLINED"
}

/// Simulcast layers of a camera: full, half and quarter resolution.
enum VideoLayer: String, Codable, Sendable {
    case full = "FULL", half = "HALF", quarter = "QUARTER"

    /// The speaker or a lone other gets the full camera; a filling grid, smaller layers.
    static func forGrid(others: Int) -> VideoLayer {
        others <= 1 ? .full : others <= 3 ? .half : .quarter
    }
}

struct CallParticipant: Codable, Hashable, Sendable {
    let userId: String
    let trackNames: [String]
}

struct Call: Codable, Hashable, Identifiable, Sendable {
    /// The tracks the apps publish, by name.
    static let audioTrack = "audio"
    static let cameraTrack = "camera"

    let id: String
    let conversationId: String
    let startedBy: String
    let media: CallMedia
    let status: CallStatus
    /// Who it rings and who may join.
    let memberIds: [String]
    /// Who is in it right now.
    let participants: [CallParticipant]

    var isLive: Bool { status == .ringing || status == .active }
}

/// A frame of `call.events`.
struct CallEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case ringing = "RINGING", participantJoined = "PARTICIPANT_JOINED", participantLeft = "PARTICIPANT_LEFT",
             tracksPublished = "TRACKS_PUBLISHED", declined = "DECLINED", ended = "ENDED"
    }

    let type: Kind
    let actorId: String
    let call: Call
}

struct IceServer: Codable, Hashable, Sendable {
    let urls: [String]
    let username: String?
    let credential: String?
}

struct CallJoin: Codable, Sendable {
    let call: Call
    let iceServers: [IceServer]
}

struct SessionDescription: Codable, Hashable, Sendable {
    let type: String
    let sdp: String
}

/// A track published on the transceiver `mid`.
struct PublishedTrack: Codable, Hashable, Sendable {
    let mid: String
    let trackName: String
}

/// A track to receive, named by who publishes it.
struct TrackRequest: Codable, Hashable, Sendable {
    let userId: String
    let trackName: String
    let layer: VideoLayer?
}

/// A received track and the transceiver it arrives on.
struct ReceivedTrack: Codable, Hashable, Sendable {
    let mid: String
    let userId: String
    let trackName: String
}

struct CallSubscription: Codable, Sendable {
    let offer: SessionDescription?
    let requiresRenegotiation: Bool
    let tracks: [ReceivedTrack]
}

struct LayerChoice: Codable, Hashable, Sendable {
    let mid: String
    let userId: String
    let trackName: String
    let layer: VideoLayer
}

/// What a VoIP push carries: enough to show the call before the app can reach the backend.
struct IncomingCallPush: Equatable, Sendable {
    let callId: String
    let caller: String
    let callerId: String?
    let media: CallMedia
    /// The call stopped ringing (the caller hung up, or nobody answered).
    let ended: Bool

    nonisolated init?(payload: [AnyHashable: Any]) {
        guard let callId = payload["callId"] as? String, !callId.isEmpty else { return nil }
        self.callId = callId
        caller = payload["caller"] as? String ?? "Wely"
        callerId = payload["callerId"] as? String
        media = (payload["media"] as? String).flatMap(CallMedia.init(rawValue:)) ?? .audio
        ended = payload["ended"] as? Bool ?? false
    }
}

struct StartCallRequest: Codable, Sendable {
    let conversationId: String
    let media: CallMedia
}

struct PublishRequest: Codable, Sendable {
    let offer: SessionDescription
    let tracks: [PublishedTrack]
}

struct SubscribeRequest: Codable, Sendable {
    let tracks: [TrackRequest]
}

struct LayersRequest: Codable, Sendable {
    let choices: [LayerChoice]
}

struct UnsubscribeRequest: Codable, Sendable {
    let mids: [String]
}
