import AuthenticationServices
import SwiftUI

/// The welcome screen: Wely's logo and the sign-in form, on the app's own screen — the same
/// composition as the Keycloak theme (brand, pitch, a narrow card on the warm canvas).
///
/// Signing up and resetting a password still open Keycloak's pages: its registration form is
/// what creates the user in wely-users, and a reset goes through an e-mail anyway.
struct LoginView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var username = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var isSigningIn = false
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    private var canSubmit: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSigningIn }

    var body: some View {
        ZStack {
            BrandBackdrop()

            ScrollView {
                VStack(spacing: 28) {
                    header
                        .padding(.top, 48)
                    form
                    signUp
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .font(.wely.body)
        .tint(Theme.primary)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(.welyLogo)
                .resizable()
                .frame(width: 84, height: 84)
                .shadow(color: Theme.gradientStops[2].opacity(0.35), radius: 18, y: 8)
                .accessibilityHidden(true)
            Text("Wely")
                .font(.wely.fixed(44, .bold))
                .tracking(-1)
            Text("Organisez vos sorties entre amis,\nsans vous perdre dans les messages.")
                .font(.wely.callout)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connexion")
                .font(.wely.title2)
            Text("Heureux de vous revoir !")
                .font(.wely.subheadline)
                .foregroundStyle(Theme.ink2)
                .padding(.top, -10)

            WelyField(systemImage: "person", isFocused: focus == .username) {
                TextField("Nom d'utilisateur ou e-mail", text: $username)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .username)
                    .onSubmit { focus = .password }
            }
            .padding(.top, 4)

            WelyField(systemImage: "lock", isFocused: focus == .password) {
                Group {
                    if showsPassword {
                        TextField("Mot de passe", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Mot de passe", text: $password)
                    }
                }
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit(signIn)
            } trailing: {
                Button { showsPassword.toggle() } label: {
                    Image(systemName: showsPassword ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.ink3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(showsPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
            }

            HStack {
                Spacer()
                Button("Mot de passe oublié ?") { openKeycloak(config: session.config.resetPasswordURL) }
                    .font(.wely.footnote.weight(.medium))
            }

            if let error = session.lastError {
                Label(error.localizedDescription, systemImage: "exclamationmark.circle.fill")
                    .font(.wely.footnote.weight(.medium))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: signIn) {
                Group {
                    if isSigningIn {
                        ProgressView().tint(.white)
                    } else {
                        Text("Se connecter")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.welyPrimary)
            .controlSize(.large)
            .disabled(!canSubmit)
            .padding(.top, 2)
        }
        .padding(22)
        .welyCard(radius: 24)
        .animation(.snappy, value: session.lastError)
    }

    private var signUp: some View {
        HStack(spacing: 4) {
            Text("Pas encore de compte ?")
                .foregroundStyle(Theme.ink2)
            Button("Créer un compte") { openKeycloak(config: nil) }
                .fontWeight(.semibold)
        }
        .font(.wely.subheadline)
    }

    private func signIn() {
        guard canSubmit else { return }
        focus = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await session.signIn(username: username, password: password)
            } catch let error as AuthError {
                session.fail(error)
                password = ""
                focus = .password
            } catch {
                session.fail(.server(error.localizedDescription))
            }
        }
    }

    /// Keycloak's sign-up form (`nil`) or another of its pages, in a web authentication session
    /// that ends signed in when the page redirects back to the app.
    private func openKeycloak(config page: URL?) {
        let url = page ?? session.beginSignIn(registration: true)
        Task {
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
                // Closed by the user: nothing to report.
            } catch let error as AuthError {
                session.fail(error)
            } catch {
                session.fail(.server(error.localizedDescription))
            }
        }
    }
}

/// A text field as wely-web's: a soft fill, a leading symbol, the brand ring when focused.
struct WelyField<Field: View, Trailing: View>: View {
    let systemImage: String
    var isFocused = false
    @ViewBuilder var field: () -> Field
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(isFocused ? Theme.primary : Theme.ink3)
                .frame(width: 22)
            field()
                .font(.wely.body)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.subtle.opacity(isFocused ? 0.4 : 0.8), in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .strokeBorder(isFocused ? Theme.blue.opacity(0.7) : Theme.border, lineWidth: isFocused ? 1.5 : 1)
        }
        .animation(.snappy(duration: 0.2), value: isFocused)
    }
}

extension WelyField where Trailing == EmptyView {
    init(systemImage: String, isFocused: Bool = false, @ViewBuilder field: @escaping () -> Field) {
        self.init(systemImage: systemImage, isFocused: isFocused, field: field) { EmptyView() }
    }
}

/// The login screen's background: the warm canvas under three slowly drifting colour fields,
/// as the Keycloak theme draws it.
struct BrandBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Theme.canvas
                    blob(Theme.gradientStops[0], size: size.width * 1.1, x: -0.15 + 0.08 * sin(t / 7), y: 0.05 + 0.05 * cos(t / 9), in: size)
                    blob(Theme.gradientStops[3], size: size.width * 0.9, x: 0.95 + 0.08 * cos(t / 8), y: 0.4 + 0.06 * sin(t / 6), in: size)
                    blob(Theme.gradientStops[6], size: size.width * 1.0, x: 0.1 + 0.1 * sin(t / 10), y: 0.98 + 0.04 * cos(t / 7), in: size)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, size: CGFloat, x: Double, y: Double, in container: CGSize) -> some View {
        Circle()
            .fill(color.opacity(0.28))
            .frame(width: size, height: size)
            .blur(radius: size * 0.28)
            .position(x: container.width * x, y: container.height * y)
    }
}

#Preview {
    LoginView().environment(AuthSession(store: InMemoryTokenStore()))
}
