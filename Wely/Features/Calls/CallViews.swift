import SwiftUI
@preconcurrency import WebRTC

/// Over every tab: the call in progress, or the one ringing.
struct CallOverlay: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var calls = app.calls
        ZStack {
            if calls.call != nil {
                CallScreen().transition(.move(edge: .bottom))
            } else if let incoming = calls.incoming {
                IncomingCallView(call: incoming).transition(.opacity)
            }
        }
        .animation(.snappy, value: calls.call?.id)
        .animation(.snappy, value: calls.incoming?.id)
        .errorAlert($calls.error)
    }
}

/// A call ringing: who calls, decline or answer.
private struct IncomingCallView: View {
    @Environment(AppModel.self) private var app
    let call: Call

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AvatarView(userId: call.startedBy, size: 112)
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 3).padding(-6))
            Text(callerName).font(.wely.title.bold())
            Label(call.media == .video ? "Appel vidéo Wely" : "Appel audio Wely",
                  systemImage: call.media == .video ? "video.fill" : "phone.fill")
                .font(.wely.subheadline)
                .opacity(0.85)
            Spacer()
            HStack(spacing: 56) {
                CallButton(symbol: "phone.down.fill", label: "Refuser", tint: Theme.danger) { app.calls.decline() }
                CallButton(symbol: call.media == .video ? "video.fill" : "phone.fill", label: "Répondre", tint: Theme.success) {
                    Task { await app.calls.join(call.id) }
                }
            }
            .padding(.bottom, 48)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.gradient.ignoresSafeArea())
    }

    /// Someone the app knows by name, else the name the call carries.
    private var callerName: String {
        app.people.directory[call.startedBy]?.name ?? call.startedByName ?? app.people.person(call.startedBy).name
    }
}

/// The call: everyone's tiles, my camera in a corner, the controls at the bottom.
private struct CallScreen: View {
    @Environment(AppModel.self) private var app

    private var calls: CallController { app.calls }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                status
                tiles
                controls
            }
            if let local = calls.localVideo, calls.cameraOn {
                VideoTrackView(track: local, mirrored: true)
                    .frame(width: 104, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.3)))
                    .padding(.top, 56)
                    .padding(.trailing, 14)
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
    }

    private var status: some View {
        Text(statusText)
            .font(.wely.subheadline)
            .opacity(0.8)
            .frame(height: 40)
    }

    private var statusText: String {
        switch calls.connection {
        case .connecting, .idle: "Connexion…"
        case .failed: "La connexion a été perdue"
        case .connected: calls.others.isEmpty ? "En attente des autres…" : (calls.call?.media == .video ? "Appel vidéo" : "Appel audio")
        }
    }

    @ViewBuilder
    private var tiles: some View {
        let others = calls.others
        if others.isEmpty {
            VStack(spacing: 14) {
                let ringing = calls.call?.memberIds.filter { $0 != app.people.myId } ?? []
                AvatarStack(userIds: ringing, limit: 4, size: 72)
                Text(ringing.map(app.people.name).joined(separator: ", ")).font(.wely.headline).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            let columns = others.count == 1 ? 1 : 2
            GeometryReader { geometry in
                let rows = Int(ceil(Double(others.count) / Double(columns)))
                let height = (geometry.size.height - CGFloat(rows - 1) * 6) / CGFloat(rows)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                    ForEach(others, id: \.userId) { participant in
                        ParticipantTile(userId: participant.userId, video: calls.remote[participant.userId]?.video)
                            .frame(height: height)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            CallButton(symbol: calls.muted ? "mic.slash.fill" : "mic.fill", tint: calls.muted ? .white.opacity(0.9) : .white.opacity(0.18),
                       foreground: calls.muted ? .black : .white, accessibility: calls.muted ? "Réactiver le micro" : "Couper le micro") {
                calls.toggleMute()
            }
            CallButton(symbol: calls.cameraOn ? "video.fill" : "video.slash.fill", tint: .white.opacity(0.18),
                       accessibility: calls.cameraOn ? "Couper la caméra" : "Activer la caméra") {
                Task { await calls.toggleCamera() }
            }
            if calls.cameraOn {
                CallButton(symbol: "arrow.triangle.2.circlepath.camera.fill", tint: .white.opacity(0.18), accessibility: "Changer de caméra") {
                    Task { await calls.flipCamera() }
                }
            }
            CallButton(symbol: calls.speakerOn ? "speaker.wave.3.fill" : "speaker.fill", tint: calls.speakerOn ? .white.opacity(0.9) : .white.opacity(0.18),
                       foreground: calls.speakerOn ? .black : .white, accessibility: "Haut-parleur") {
                calls.toggleSpeaker()
            }
            CallButton(symbol: "phone.down.fill", tint: Theme.danger, accessibility: "Raccrocher") {
                Task { await calls.leave() }
            }
        }
        .padding(.vertical, 20)
    }
}

/// Someone's camera, or their avatar while it is off.
private struct ParticipantTile: View {
    @Environment(AppModel.self) private var app
    let userId: String
    let video: RTCVideoTrack?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let video {
                VideoTrackView(track: video)
            } else {
                Color.white.opacity(0.08)
                AvatarView(userId: userId, size: 84).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(app.people.person(userId).name)
                .font(.wely.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A round call control, with its label under it when there is one.
private struct CallButton: View {
    let symbol: String
    var label: String?
    let tint: Color
    var foreground: Color = .white
    var accessibility: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: label == nil ? 58 : 72, height: label == nil ? 58 : 72)
                    .background(tint, in: Circle())
            }
            .accessibilityLabel(accessibility ?? label ?? "")
            if let label { Text(label).font(.wely.footnote) }
        }
    }
}
