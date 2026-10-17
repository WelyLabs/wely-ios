import SwiftUI
@preconcurrency import WebRTC

/// Shows a WebRTC video track, filling its frame.
struct VideoTrackView: UIViewRepresentable {
    let track: RTCVideoTrack
    var mirrored = false

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        view.clipsToBounds = true
        track.add(view)
        context.coordinator.track = track
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        guard context.coordinator.track !== track else { return }
        context.coordinator.track?.remove(view)
        track.add(view)
        context.coordinator.track = track
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var track: RTCVideoTrack?
    }
}
