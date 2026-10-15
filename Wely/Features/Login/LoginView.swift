import AuthenticationServices
import SwiftUI

/// The welcome screen: one button that opens Keycloak's login page (which also offers to sign up).
struct LoginView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isSigningIn = false

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Wely")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Organisez vos sorties entre amis,\nsans vous perdre dans les messages.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()

                if let error = session.lastError {
                    Text(error.localizedDescription)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                        .multilineTextAlignment(.center)
                }

                Button(action: signIn) {
                    Group {
                        if isSigningIn {
                            ProgressView().tint(Theme.blue)
                        } else {
                            Text("Se connecter")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.blue)
                }
                .disabled(isSigningIn)

                Text("Pas encore de compte ? Créez-le depuis la page de connexion.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private func signIn() {
        isSigningIn = true
        let url = session.beginSignIn()
        Task {
            defer { isSigningIn = false }
            do {
                // Ephemeral: no shared Safari cookies, so no « Wely wants to sign in » prompt.
                let callback = try await webAuthenticationSession.authenticate(
                    using: url,
                    callback: .customScheme(session.config.callbackScheme),
                    preferredBrowserSession: .ephemeral,
                    additionalHeaderFields: [:]
                )
                try await session.completeSignIn(callback: callback)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                session.fail(.cancelled)
            } catch let error as AuthError {
                session.fail(error)
            } catch {
                session.fail(.server(error.localizedDescription))
            }
        }
    }
}

#Preview {
    LoginView().environment(AuthSession(store: InMemoryTokenStore()))
}
