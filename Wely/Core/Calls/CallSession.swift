import Foundation
@preconcurrency import WebRTC

/// How a session reaches the relay: through wely-chat, which holds the relay's secret.
protocol CallSignaling {
    func publish(offer: SessionDescription, tracks: [PublishedTrack]) async throws -> SessionDescription
    func subscribe(_ requests: [TrackRequest]) async throws -> CallSubscription
    func renegotiate(answer: SessionDescription) async throws
}

/// A local track to publish under a name; a camera goes out in three simulcast layers.
struct LocalPublication {
    let name: String
    let track: RTCMediaStreamTrack
    var simulcast = false
}

enum CallSessionError: LocalizedError {
    case transceiver

    var errorDescription: String? { "La connexion à l'appel a échoué." }
}

/// The phone's WebRTC connection to the relay: it publishes its own tracks there and receives
/// everyone else's from it, on a single peer connection — what wely-web's `CallSession` does.
///
/// Negotiations run one at a time: publishing and subscribing both change the session
/// description, and two overlapping offer/answer exchanges would leave it in a state neither
/// side expects.
final class CallSession {
    static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                        decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    /// Full, half and quarter resolution, with the rids wely-chat asks the relay for.
    static func simulcastLayers() -> [RTCRtpEncodingParameters] {
        [("f", 1.0, 1_200_000), ("h", 2.0, 400_000), ("q", 4.0, 150_000)].map { rid, scale, bitrate in
            let layer = RTCRtpEncodingParameters()
            layer.rid = rid
            layer.scaleResolutionDownBy = NSNumber(value: scale)
            layer.maxBitrateBps = NSNumber(value: bitrate)
            return layer
        }
    }

    var onRemoteTrack: ((ReceivedTrack, RTCMediaStreamTrack) -> Void)?
    var onConnectionState: ((RTCPeerConnectionState) -> Void)?

    private let peer: RTCPeerConnection
    private let signaling: CallSignaling
    private let observer = PeerObserver()
    private var queue: Task<Void, Never>?
    /// Who sends what arrives on each receiving transceiver.
    private var receiving: [String: ReceivedTrack] = [:]
    private var senders: [String: RTCRtpSender] = [:]
    private static let noConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

    init(iceServers: [IceServer], signaling: CallSignaling) throws {
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        guard let peer = Self.factory.peerConnection(with: configuration, constraints: Self.noConstraints, delegate: observer) else {
            throw CallSessionError.transceiver
        }
        self.peer = peer
        self.signaling = signaling
        observer.onTransceiver = { [weak self] transceiver in
            Task { @MainActor in self?.started(transceiver) }
        }
        observer.onState = { [weak self] state in
            Task { @MainActor in self?.onConnectionState?(state) }
        }
    }

    /// Sends tracks: the phone's offer goes to the relay, whose answer completes the exchange.
    func publish(_ publications: [LocalPublication]) async throws {
        try await serialized { [self] in
            var added: [(RTCRtpTransceiver, String)] = []
            for publication in publications {
                let options = RTCRtpTransceiverInit()
                options.direction = .sendOnly
                if publication.simulcast { options.sendEncodings = Self.simulcastLayers() }
                guard let transceiver = peer.addTransceiver(with: publication.track, init: options) else {
                    throw CallSessionError.transceiver
                }
                senders[publication.name] = transceiver.sender
                added.append((transceiver, publication.name))
            }
            let offer = try await peer.offer(for: Self.noConstraints)
            try await peer.setLocalDescription(offer)
            // A transceiver only gets its mid once the offer is set locally.
            let answer = try await signaling.publish(
                offer: SessionDescription(type: "offer", sdp: offer.sdp),
                tracks: added.map { PublishedTrack(mid: $0.0.mid, trackName: $0.1) })
            try await peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer.sdp))
        }
    }

    /// Receives tracks. The relay answers with the transceivers they will arrive on, and usually
    /// with an offer of its own, which the phone answers before any media flows.
    func subscribe(_ requests: [TrackRequest]) async throws -> [ReceivedTrack] {
        guard !requests.isEmpty else { return [] }
        return try await serialized { [self] in
            let subscription = try await signaling.subscribe(requests)
            // Known before the offer is applied: tracks start arriving while it is.
            for track in subscription.tracks { receiving[track.mid] = track }
            if subscription.requiresRenegotiation, let offer = subscription.offer {
                try await peer.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: offer.sdp))
                let answer = try await peer.answer(for: Self.noConstraints)
                try await peer.setLocalDescription(answer)
                try await signaling.renegotiate(answer: SessionDescription(type: "answer", sdp: answer.sdp))
            }
            return subscription.tracks
        }
    }

    /// Swaps what a published track sends, such as no camera, without renegotiating.
    func replaceTrack(_ name: String, with track: RTCMediaStreamTrack?) {
        senders[name]?.track = track
    }

    func publishes(_ name: String) -> Bool { senders[name] != nil }

    /// Forgets the transceivers of someone who left.
    func forget(_ mids: [String]) {
        mids.forEach { receiving.removeValue(forKey: $0) }
    }

    func close() {
        observer.onTransceiver = nil
        observer.onState = nil
        peer.close()
    }

    private func started(_ transceiver: RTCRtpTransceiver) {
        guard let owner = receiving[transceiver.mid], let track = transceiver.receiver.track else { return }
        onRemoteTrack?(owner, track)
    }

    private func serialized<T: Sendable>(_ step: @escaping () async throws -> T) async throws -> T {
        let previous = queue
        let run = Task {
            await previous?.value
            return try await step()
        }
        queue = Task { _ = try? await run.value }
        return try await run.value
    }
}

/// WebRTC calls its delegate on its own thread; this hands each event on, unisolated.
private final class PeerObserver: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    nonisolated(unsafe) var onTransceiver: ((RTCRtpTransceiver) -> Void)?
    nonisolated(unsafe) var onState: ((RTCPeerConnectionState) -> Void)?

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        onTransceiver?(transceiver)
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        onState?(newState)
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
