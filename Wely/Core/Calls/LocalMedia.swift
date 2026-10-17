import AVFoundation
@preconcurrency import WebRTC

enum LocalMediaError: LocalizedError {
    case microphoneDenied, cameraDenied, noCamera

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Autorisez le micro dans Réglages › Wely pour appeler."
        case .cameraDenied: "Autorisez la caméra dans Réglages › Wely pour la vidéo."
        case .noCamera: "Aucune caméra disponible sur cet appareil."
        }
    }
}

/// The phone's microphone and camera, as WebRTC tracks.
final class LocalMedia {
    let audio: RTCAudioTrack
    private(set) var video: RTCVideoTrack?
    private(set) var position: AVCaptureDevice.Position = .front
    private let videoSource: RTCVideoSource
    private let capturer: RTCCameraVideoCapturer

    init() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw LocalMediaError.microphoneDenied }
        let factory = CallSession.factory
        audio = factory.audioTrack(with: factory.audioSource(with: nil), trackId: Call.audioTrack)
        videoSource = factory.videoSource()
        capturer = RTCCameraVideoCapturer(delegate: videoSource)
    }

    /// Starts the camera and answers its track, the same one across flips and restarts.
    func startCamera() async throws -> RTCVideoTrack {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw LocalMediaError.cameraDenied }
        try await capture(from: position)
        if let video { return video }
        let track = CallSession.factory.videoTrack(with: videoSource, trackId: Call.cameraTrack)
        video = track
        return track
    }

    /// Stops the camera, so its light goes out.
    func stopCamera() async {
        await capturer.stopCapture()
    }

    /// Front to back camera and back.
    func flipCamera() async throws {
        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        try await capture(from: next)
        position = next
    }

    func stop() {
        capturer.stopCapture()
        audio.isEnabled = false
        video?.isEnabled = false
    }

    private func capture(from position: AVCaptureDevice.Position) async throws {
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == position }) ?? devices.first else { throw LocalMediaError.noCamera }
        // 720p at most: the full simulcast layer, and the camera stays cool.
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let format = formats.last { CMVideoFormatDescriptionGetDimensions($0.formatDescription).height <= 720 } ?? formats.first
        guard let format else { throw LocalMediaError.noCamera }
        let fps = min(30, Int(format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30))
        try await capturer.startCapture(with: device, format: format, fps: fps)
    }
}
