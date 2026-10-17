import AVFoundation
@preconcurrency import CallKit
@preconcurrency import PushKit
@preconcurrency import WebRTC

/// Incoming calls as iOS shows them, the way WhatsApp does: a VoIP push (PushKit) wakes the app,
/// even closed, and CallKit rings with the system's own full-screen call, on the lock screen too.
///
/// iOS requires every VoIP push to be reported to CallKit at once, or it stops delivering them;
/// so the push carries the caller and the media, and the backend is only reached on answer.
/// PushKit, like APNs, needs a paid Apple Developer team: without it, no token ever arrives
/// and calls keep ringing in the app only.
final class SystemCalls: NSObject {
    /// Answer: join the call with this media.
    var onAnswer: ((String, CallMedia) async -> Void)?
    /// Declined from the system screen before answering.
    var onDecline: ((String) -> Void)?
    /// Hung up from the system screen during the call.
    var onHangUp: (() async -> Void)?
    /// The system screen's mute button.
    var onMute: ((Bool) -> Void)?

    private let service: NotificationService
    private let registry = PKPushRegistry(queue: .main)
    private let provider: CXProvider
    private let controller = CXCallController()
    /// CallKit's id for each Wely call it shows, and back.
    private var uuids: [String: UUID] = [:]
    private var answered: Set<String> = []

    init(service: NotificationService) {
        self.service = service
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.iconTemplateImageData = UIImage(named: "WelyLogo")?.pngData()
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    /// Whether the system screen already shows this call, so the app does not ring it twice.
    func isShowing(_ callId: String) -> Bool { uuids[callId] != nil }

    /// The call ended elsewhere (the caller hung up, someone else answered on another device).
    func callEnded(_ callId: String, reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = uuids.removeValue(forKey: callId) else { return }
        answered.remove(callId)
        provider.reportCall(with: uuid, endedAt: nil, reason: reason)
        Self.manualAudio(false)
    }

    /// The app hung up: the system call ends with it.
    func hungUp(_ callId: String) {
        guard let uuid = uuids[callId] else { return }
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { _ in }
    }

    private func report(_ push: IncomingCallPush, completion: @escaping () -> Void) {
        if push.ended {
            callEnded(push.callId, reason: .unanswered)
            return completion()
        }
        let uuid = uuids[push.callId] ?? UUID()
        uuids[push.callId] = uuid
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: push.callerId ?? push.callId)
        update.localizedCallerName = push.caller
        update.hasVideo = push.media == .video
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        media[push.callId] = push.media
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if error != nil { self?.uuids.removeValue(forKey: push.callId) }
            completion()
        }
    }

    private var media: [String: CallMedia] = [:]

    private func callId(for uuid: UUID) -> String? {
        uuids.first { $0.value == uuid }?.key
    }

    /// With CallKit, iOS activates the audio session: WebRTC must wait for it.
    private static func manualAudio(_ on: Bool) {
        let audio = RTCAudioSession.sharedInstance()
        audio.useManualAudio = on
        audio.isAudioEnabled = !on
    }
}

extension SystemCalls: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        MainActor.assumeIsolated {
            let device = ApnsDeviceRequest(token: token, environment: DevicePush.environment, kind: .voip)
            Task { [service] in try? await service.registerDevice(device) }
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                                  for type: PKPushType, completion: @escaping () -> Void) {
        let push = IncomingCallPush(payload: payload.dictionaryPayload)
        // PushKit calls on the main queue (set in init) and waits for it: no race to fear.
        nonisolated(unsafe) let completion = completion
        MainActor.assumeIsolated {
            guard let push else {
                // Still reported: iOS punishes a VoIP push that shows no call.
                let uuid = UUID()
                provider.reportNewIncomingCall(with: uuid, update: CXCallUpdate()) { [provider] _ in
                    provider.reportCall(with: uuid, endedAt: nil, reason: .failed)
                    completion()
                }
                return
            }
            report(push, completion: completion)
        }
    }
}

extension SystemCalls: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            uuids = [:]
            answered = []
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
            guard let callId = callId(for: action.callUUID) else { return action.fail() }
            answered.insert(callId)
            Self.manualAudio(true)
            action.fulfill()
            let media = media[callId] ?? .audio
            Task { await onAnswer?(callId, media) }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated {
            guard let callId = callId(for: action.callUUID) else { return action.fulfill() }
            uuids.removeValue(forKey: callId)
            if answered.remove(callId) != nil {
                Task { await onHangUp?() }
            } else {
                onDecline?(callId)
            }
            Self.manualAudio(false)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        MainActor.assumeIsolated {
            onMute?(action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        let audio = RTCAudioSession.sharedInstance()
        audio.audioSessionDidActivate(audioSession)
        audio.isAudioEnabled = true
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        let audio = RTCAudioSession.sharedInstance()
        audio.audioSessionDidDeactivate(audioSession)
        audio.isAudioEnabled = false
    }
}
