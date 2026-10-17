import SwiftUI

/// Over the screens while Wely is locked, or out of sight with the lock on (the app switcher
/// shows this instead of a conversation).
struct AppLockOverlay: View {
    @Environment(AppModel.self) private var app

    private var lock: AppLock { app.lock }

    /// Shared with the screens behind, so both move as one.
    static let unlocking = Animation.smooth(duration: 0.5)

    var body: some View {
        ZStack {
            if lock.isCovering {
                cover
                    // Lifts off towards the user; appears at once, so the app switcher never
                    // catches the screens behind half covered.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.12))))
            }
        }
        // On covering, not on locking: Face ID's prompt hides the app, and either may end first.
        .animation(Self.unlocking, value: lock.isCovering)
        .sensoryFeedback(.success, trigger: lock.isLocked) { wasLocked, isLocked in wasLocked && !isLocked }
    }

    private var cover: some View {
        Group {
            VStack(spacing: 20) {
                Spacer()
                Image("WelyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                Text("Wely est verrouillée").font(.wely.title2.bold())
                Spacer()
                if lock.isLocked {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Déverrouiller", systemImage: lock.biometryName == "Touch ID" ? "touchid" : "faceid")
                    }
                    .buttonStyle(.welyPrimary)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas.ignoresSafeArea())
            // Face ID at once, each time Wely comes back on screen locked.
            .task(id: lock.isLocked && !lock.isHidden) {
                if lock.isLocked && !lock.isHidden { await lock.unlock() }
            }
        }
    }
}
