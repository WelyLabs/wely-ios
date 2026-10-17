import AVFoundation
import Observation
@preconcurrency import WebRTC

/// What arrives from someone else in the call.
struct RemoteMedia {
    var audio: RTCAudioTrack?
    var video: RTCVideoTrack?
}

/// Audio and video calls, from ringing to hanging up — wely-web's `CallService`, on the phone.
///
/// wely-chat decides who may do what and holds the relay's secret: this asks it for each step,
/// and runs the phone's side — the microphone and camera, the one WebRTC connection to the relay
/// (`CallSession`), the heartbeat that keeps the user in the call, and the ringing.
@Observable
final class CallController {
    enum Connection { case idle, connecting, connected, failed }

    /// A call ringing for the user, until they answer, decline or it stops.
    private(set) var incoming: Call?
    /// The call the user is in.
    private(set) var call: Call?
    private(set) var connection = Connection.idle
    private(set) var remote: [String: RemoteMedia] = [:]
    private(set) var localVideo: RTCVideoTrack?
    private(set) var muted = false
    private(set) var cameraOn = false
    private(set) var speakerOn = false
    /// Why the last step failed, for an alert.
    var error: String?

    @ObservationIgnored private let service: CallService
    @ObservationIgnored private let socket: ChatSocket
    @ObservationIgnored private let myId: () -> String?
    @ObservationIgnored private var session: CallSession?
    @ObservationIgnored private var media: LocalMedia?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private let ringer = Ringer()
    /// `userId:trackName` to the mid it arrives on; empty while asked for.
    @ObservationIgnored private var subscribed: [String: String] = [:]

    static let heartbeatInterval = Duration.seconds(15)

    /// Whether iOS's own call screen (CallKit) already rings this call.
    @ObservationIgnored var isShownBySystem: (String) -> Bool = { _ in false }
    /// A call ended here, for CallKit to close its screen.
    @ObservationIgnored var onCallEnded: ((String, _ answered: Bool) -> Void)?

    init(service: CallService, socket: ChatSocket, myId: @escaping () -> String?) {
        self.service = service
        self.socket = socket
        self.myId = myId
    }

    /// Everyone else in the call, in the order they joined.
    var others: [CallParticipant] {
        let me = myId()
        return (call?.participants ?? []).filter { $0.userId != me }
    }

    /// Starts listening for calls, once signed in.
    func listen() {
        guard listening == nil else { return }
        listening = Task { [weak self] in
            guard let events = self?.socket.callEvents() else { return }
            for await event in events { self?.handle(event) }
        }
    }

    func stopListening() {
        listening?.cancel()
        listening = nil
        stopRinging()
        teardown()
    }

    /// Calls a conversation's members, or joins the call already going on there.
    func start(conversationId: String, media: CallMedia) async {
        do {
            let call = try await service.start(conversationId: conversationId, media: media)
            await join(call.id, media: media)
        } catch {
            explain(error)
        }
    }

    /// Enters a call: the server first, then the microphone (and camera), then the relay.
    func join(_ callId: String, media requested: CallMedia? = nil) async {
        if call?.id == callId { return }
        if call != nil { await leave() }
        stopRinging()
        connection = .connecting
        do {
            let joined = try await service.join(callId)
            let withVideo = (requested ?? joined.call.media) == .video
            let local: LocalMedia
            do {
                local = try await LocalMedia()
            } catch {
                try? await service.leave(callId)
                throw error
            }
            media = local
            call = joined.call
            configureAudio(video: withVideo)
            try connect(joined)
            var publications = [LocalPublication(name: Call.audioTrack, track: local.audio)]
            if withVideo, let camera = try? await local.startCamera() {
                publications.append(LocalPublication(name: Call.cameraTrack, track: camera, simulcast: true))
                localVideo = camera
                cameraOn = true
            }
            try await session?.publish(publications)
            for participant in others { await receive(from: participant.userId) }
        } catch {
            explain(error)
            if call?.id == callId { await leave() } else { teardown() }
        }
    }

    /// Refuses a ringing call.
    func decline() {
        guard let incoming else { return }
        decline(incoming.id)
    }

    /// Refuses a call by id, such as one declined on iOS's call screen.
    func decline(_ callId: String) {
        if incoming?.id == callId { stopRinging() }
        Task { [service] in try? await service.decline(callId) }
    }

    /// Hangs up: the call ends here whatever the server answers.
    func leave() async {
        guard let call else { return teardown() }
        teardown()
        try? await service.leave(call.id)
    }

    /// The conversation's live call, for a "Join" bar.
    func live(conversationId: String) async -> Call? {
        try? await service.live(conversationId: conversationId)
    }

    func toggleMute() { setMuted(!muted) }

    func setMuted(_ on: Bool) {
        muted = on
        media?.audio.isEnabled = !on
    }

    /// Off stops the camera, so its light goes out; on, in a call started without video, it is
    /// published for the first time.
    func toggleCamera() async {
        guard let media, let session else { return }
        if cameraOn {
            session.replaceTrack(Call.cameraTrack, with: nil)
            await media.stopCamera()
            cameraOn = false
            localVideo = nil
            return
        }
        do {
            let camera = try await media.startCamera()
            if session.publishes(Call.cameraTrack) {
                session.replaceTrack(Call.cameraTrack, with: camera)
            } else {
                try await session.publish([LocalPublication(name: Call.cameraTrack, track: camera, simulcast: true)])
            }
            localVideo = camera
            cameraOn = true
            if !speakerOn { toggleSpeaker() }
        } catch {
            explain(error)
        }
    }

    func flipCamera() async {
        do { try await media?.flipCamera() } catch { explain(error) }
    }

    /// Loudspeaker or earpiece.
    func toggleSpeaker() {
        speakerOn.toggle()
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        try? audio.overrideOutputAudioPort(speakerOn ? .speaker : .none)
        audio.unlockForConfiguration()
    }

    // MARK: Events

    private func handle(_ event: CallEvent) {
        let inCall = call?.id == event.call.id
        switch event.type {
        case .ringing:
            if call == nil, event.call.startedBy != myId(), !isShownBySystem(event.call.id) {
                incoming = event.call
                ringer.start()
            }
        case .ended:
            if incoming?.id == event.call.id { stopRinging() }
            if !inCall { onCallEnded?(event.call.id, false) }
            if inCall { teardown() }
        case .declined:
            // A one-to-one call the other declined ends with an ENDED event; nothing to do here.
            break
        case .participantJoined:
            if !inCall, event.actorId == myId() {
                // Answered on another device: stop ringing here.
                if incoming?.id == event.call.id { stopRinging() }
                onCallEnded?(event.call.id, false)
            }
            if inCall {
                call = event.call
                relayer()
            }
        case .tracksPublished:
            if inCall {
                call = event.call
                Task { await receive(from: event.actorId) }
            }
        case .participantLeft:
            if inCall {
                call = event.call
                forget(event.actorId)
                relayer()
            }
        }
    }

    // MARK: Connection

    private func connect(_ joined: CallJoin) throws {
        let callId = joined.call.id
        let session = try CallSession(iceServers: joined.iceServers, signaling: Signaling(service: service, callId: callId))
        self.session = session
        session.onRemoteTrack = { [weak self] track, media in self?.received(track, media) }
        session.onConnectionState = { [weak self] state in
            switch state {
            case .connected: self?.connection = .connected
            case .failed: self?.connection = .failed
            default: break
            }
        }
        heartbeat = Task { [weak self, service] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled else { return }
                do {
                    try await service.heartbeat(callId)
                } catch let error as APIError where error.status == 404 {
                    // The call ended, or this user was dropped while offline.
                    if self?.call?.id == callId { self?.teardown() }
                    return
                } catch {}
            }
        }
    }

    /// Subscribes to what someone publishes that is not received yet.
    private func receive(from userId: String) async {
        guard let session, let call, let participant = call.participants.first(where: { $0.userId == userId }) else { return }
        let layer = VideoLayer.forGrid(others: others.count)
        let requests = participant.trackNames
            .filter { subscribed["\(userId):\($0)"] == nil }
            .map { TrackRequest(userId: userId, trackName: $0, layer: $0 == Call.cameraTrack ? layer : nil) }
        requests.forEach { subscribed["\($0.userId):\($0.trackName)"] = "" }
        do {
            let received = try await session.subscribe(requests)
            received.forEach { subscribed["\($0.userId):\($0.trackName)"] = $0.mid }
        } catch {
            requests.forEach { subscribed.removeValue(forKey: "\($0.userId):\($0.trackName)") }
        }
    }

    private func received(_ track: ReceivedTrack, _ media: RTCMediaStreamTrack) {
        var entry = remote[track.userId] ?? RemoteMedia()
        if let audio = media as? RTCAudioTrack { entry.audio = audio }
        if let video = media as? RTCVideoTrack { entry.video = video }
        remote[track.userId] = entry
    }

    /// Someone left: their tile goes, and the relay stops sending what came from them.
    private func forget(_ userId: String) {
        let keys = subscribed.keys.filter { $0.hasPrefix("\(userId):") }
        let mids = keys.compactMap { subscribed.removeValue(forKey: $0) }.filter { !$0.isEmpty }
        remote.removeValue(forKey: userId)
        session?.forget(mids)
        if let call, !mids.isEmpty {
            Task { [service] in try? await service.unsubscribe(call.id, mids: mids) }
        }
    }

    /// As the grid fills up or empties, every received camera moves to the layer its tile needs.
    private func relayer() {
        guard let call else { return }
        let layer = VideoLayer.forGrid(others: others.count)
        let choices = subscribed.compactMap { key, mid -> LayerChoice? in
            guard !mid.isEmpty, key.hasSuffix(":\(Call.cameraTrack)") else { return nil }
            return LayerChoice(mid: mid, userId: String(key.dropLast(Call.cameraTrack.count + 1)), trackName: Call.cameraTrack, layer: layer)
        }
        guard !choices.isEmpty else { return }
        Task { [service] in try? await service.chooseLayers(call.id, choices) }
    }

    // MARK: Media

    private func configureAudio(video: Bool) {
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        try? audio.setCategory(.playAndRecord, with: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try? audio.setMode(video ? .videoChat : .voiceChat)
        audio.unlockForConfiguration()
        speakerOn = false
        // A video call is held at arm's length: loudspeaker; an audio call, at the ear.
        if video { toggleSpeaker() }
    }

    private func stopRinging() {
        ringer.stop()
        incoming = nil
    }

    /// Everything back to idle: no connection, no microphone, no heartbeat.
    private func teardown() {
        if let call { onCallEnded?(call.id, true) }
        heartbeat?.cancel()
        heartbeat = nil
        session?.close()
        session = nil
        media?.stop()
        media = nil
        localVideo = nil
        remote = [:]
        subscribed = [:]
        muted = false
        cameraOn = false
        speakerOn = false
        call = nil
        connection = .idle
    }

    /// Tells the user why a call could not go on, in their words.
    private func explain(_ error: Error) {
        switch (error as? APIError)?.code {
        case "CHT-BUS-009": self.error = "L'appel est complet."
        case "CHT-BUS-008": self.error = "Cet appel est terminé."
        default:
            if let media = error as? LocalMediaError {
                self.error = media.errorDescription
            } else if error is APIError {
                self.error = error.localizedDescription
            } else {
                self.error = "Les appels sont indisponibles pour le moment."
            }
        }
    }
}

/// The signaling steps of one call, through wely-chat.
private struct Signaling: CallSignaling {
    let service: CallService
    let callId: String

    func publish(offer: SessionDescription, tracks: [PublishedTrack]) async throws -> SessionDescription {
        try await service.publish(callId, offer: offer, tracks: tracks)
    }
    func subscribe(_ requests: [TrackRequest]) async throws -> CallSubscription {
        try await service.subscribe(callId, tracks: requests)
    }
    func renegotiate(answer: SessionDescription) async throws {
        try await service.renegotiate(callId, answer: answer)
    }
}
