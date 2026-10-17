import SwiftUI

/// The account's preferences, as wely-web's page: the theme, the notifications, and deleting
/// the account. A choice applies at once, then is kept with the account; a refused save puts
/// the previous value back and says so.
struct PreferencesView: View {
    @Environment(AppModel.self) private var app
    @State private var notificationPrefs: NotificationPreferences?
    @State private var prefsError: String?
    @State private var themeError: String?
    @State private var savingTheme = false
    /// Nil while wely-users has not answered.
    @State private var deletionAllowed: Bool?
    @State private var deletionUnavailable = false
    @State private var deleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Gardées avec votre compte, sur tous vos appareils.")
                    .font(.wely.subheadline)
                    .foregroundStyle(Theme.ink2)

                themeCard
                notificationsCard
                accountCard
                aboutCard
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Préférences")
        .task { await load() }
        .sheet(isPresented: $deleting) { DeleteAccountSheet() }
    }

    // MARK: Theme

    private var themeCard: some View {
        PreferenceCard(title: "Thème", hint: "L'apparence de Wely.") {
            HStack(spacing: 10) {
                ForEach(ThemePreference.allCases, id: \.self) { option in
                    ThemeOption(option: option, selected: app.theme == option) { choose(option) }
                        .disabled(savingTheme)
                }
            }
            if let themeError { ErrorLine(text: themeError) }
        }
    }

    private func choose(_ option: ThemePreference) {
        guard option != app.theme, !savingTheme else { return }
        savingTheme = true
        themeError = nil
        Task {
            defer { savingTheme = false }
            do {
                try await app.chooseTheme(option)
            } catch {
                themeError = "Le thème n'a pas pu être enregistré. Réessayez dans un instant."
            }
        }
    }

    // MARK: Notifications

    private var notificationsCard: some View {
        PreferenceCard(title: "Notifications", hint: "Ce dont Wely vous prévient, dans le centre de notifications.") {
            if let binding = Binding($notificationPrefs) {
                VStack(spacing: 0) {
                    PreferenceToggle(title: "Appels", detail: "Quand on vous appelle, et les appels manqués.", isOn: binding.calls)
                    Divider()
                    PreferenceToggle(title: "Messages", detail: "Les nouveaux messages de vos discussions.", isOn: binding.messages)
                    Divider()
                    PreferenceToggle(title: "Événements", detail: "Une date fixée ou un événement déplacé.", isOn: binding.events)
                    Divider()
                    PreferenceToggle(title: "Amis", detail: "Les demandes d'ami et celles acceptées.", isOn: binding.friends)
                }
            } else if prefsError == nil {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            devicePush
            if let prefsError { ErrorLine(text: prefsError) }
        }
        .onChange(of: notificationPrefs) { old, new in
            guard let old, let new, old != new else { return }
            Task {
                do {
                    try await app.notificationService.savePreferences(new)
                    prefsError = nil
                } catch {
                    notificationPrefs = old
                    prefsError = "Ce réglage n'a pas pu être enregistré. Réessayez dans un instant."
                }
            }
        }
    }

    /// This iPhone's permission, and what it gets without a paid Apple team.
    @ViewBuilder
    private var devicePush: some View {
        switch app.push.permission {
        case .notDetermined:
            AsyncButton("Activer sur cet iPhone") { await app.push.enable() }
                .buttonStyle(.welySecondary)
        case .denied:
            Button("Autoriser dans Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.welySecondary)
        case .allowed, .unknown:
            EmptyView()
        }
        if app.push.permission == .allowed {
            Label(app.push.remoteAvailable
                  ? "Activées sur cet iPhone."
                  : "Activées sur cet iPhone tant que Wely est ouverte ou vient de passer en arrière-plan. Quand l'app est fermée, il faudra la version publiée sur l'App Store.",
                  systemImage: "iphone.radiowaves.left.and.right")
                .font(.wely.footnote)
                .foregroundStyle(Theme.ink2)
        }
    }

    // MARK: Account

    private var accountCard: some View {
        PreferenceCard(title: "Compte", hint: "Supprimer votre compte efface votre profil et vos données personnelles. Vos messages restent visibles par ceux à qui vous les avez envoyés, sous « Utilisateur supprimé ».") {
            Button(role: .destructive) { deleting = true } label: {
                Label("Supprimer mon compte", systemImage: "trash")
            }
            .buttonStyle(.welyDanger)
            .disabled(deletionAllowed != true || app.people.me == nil)
            if deletionAllowed == false {
                Text("Le compte de démonstration ne peut pas être supprimé.").font(.wely.footnote).foregroundStyle(Theme.ink2)
            }
            if deletionUnavailable {
                Text("La suppression du compte est indisponible pour le moment.").font(.wely.footnote).foregroundStyle(Theme.ink2)
            }
        }
    }

    private var aboutCard: some View {
        PreferenceCard(title: "À propos", hint: nil) {
            VStack(spacing: 10) {
                LabeledContent("Version", value: Bundle.main.appVersion)
                LabeledContent("Serveur", value: app.session.config.gatewayURL.host() ?? "—")
                if app.isDemo { LabeledContent("Mode", value: "Démo") }
            }
            .font(.wely.subheadline)
        }
    }

    private func load() async {
        // Read again here: the user may have changed it in Settings since.
        Task { await app.push.refresh() }
        async let prefs = app.notificationService.preferences()
        async let eligibility = app.users.deletionEligibility()
        do { notificationPrefs = try await prefs } catch { prefsError = "Vos réglages de notifications n'ont pas pu être chargés." }
        do { deletionAllowed = try await eligibility.allowed } catch { deletionUnavailable = true }
    }
}

// MARK: Pieces

/// A titled white card, as each section of wely-web's preferences.
private struct PreferenceCard<Content: View>: View {
    let title: String
    let hint: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.wely.headline)
                if let hint {
                    Text(hint).font(.wely.footnote).foregroundStyle(Theme.ink2)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .welyCard()
    }
}

/// One theme: a small drawing of the app in it, its name, a check when chosen.
private struct ThemeOption: View {
    let option: ThemePreference
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
                HStack(spacing: 4) {
                    Image(systemName: option.systemImage)
                    Text(option.label)
                }
                .font(.wely.footnote.weight(.semibold))
                .foregroundStyle(selected ? Theme.primary : Theme.ink)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.blue.opacity(0.08) : Theme.subtle.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.primary : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Theme.primary)
                        .font(.system(size: 18))
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thème \(option.label)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var preview: some View {
        switch option {
        case .light: MiniApp(dark: false)
        case .dark: MiniApp(dark: true)
        case .system:
            HStack(spacing: 0) {
                MiniApp(dark: false)
                MiniApp(dark: true)
            }
        }
    }
}

/// The app drawn in a few strokes: the canvas, a gradient bar, two lines of text.
private struct MiniApp: View {
    let dark: Bool

    var body: some View {
        let canvas = dark ? Color(hex: 0x121214) : Color(hex: 0xFCFAF7)
        let line = dark ? Color.white.opacity(0.18) : Color.black.opacity(0.1)
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Theme.horizontalGradient).frame(height: 6)
            Capsule().fill(line).frame(height: 4)
            Capsule().fill(line).frame(width: 24, height: 4)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvas)
    }
}

private struct PreferenceToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.wely.body.weight(.medium))
                Text(detail).font(.wely.caption).foregroundStyle(Theme.ink2)
            }
        }
        .tint(Theme.primary)
        .padding(.vertical, 10)
    }
}

private struct ErrorLine: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.wely.footnote.weight(.medium))
            .foregroundStyle(Theme.danger)
    }
}

// MARK: Deletion

/// The last step before deleting the account: what it does, the handle typed to confirm, and
/// the password — the sign-in it gives is what wely-users wants under five minutes old.
private struct DeleteAccountSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var typedHandle = ""
    @State private var password = ""
    @State private var running = false
    @State private var error: String?

    private var me: UserProfile? { app.people.me }
    private var handle: String { me.map { "\($0.userName)#\($0.hashtag)" } ?? "" }
    private var canDelete: Bool { !handle.isEmpty && typedHandle.trimmingCharacters(in: .whitespaces) == handle && !password.isEmpty && !running }

    var body: some View {
        WelyNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("La suppression est immédiate et définitive.")
                        .font(.wely.subheadline)
                        .foregroundStyle(Theme.ink2)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(AccountDeletionOutcome.consequences, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(Theme.danger).frame(width: 6, height: 6)
                                Text(line).font(.wely.subheadline)
                            }
                        }
                    }
                    .padding(16)
                    .welyCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pour confirmer, tapez \(Text(handle).bold())").font(.wely.subheadline)
                        WelyField(systemImage: "number") {
                            TextField(handle, text: $typedHandle)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Text("Puis votre mot de passe").font(.wely.subheadline).padding(.top, 6)
                        WelyField(systemImage: "lock") {
                            SecureField("Mot de passe", text: $password).textContentType(.password)
                        }
                    }

                    if let error { ErrorLine(text: error) }

                    Button(action: delete) {
                        Group {
                            if running { ProgressView().tint(.white) } else { Text("Supprimer définitivement") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.welyDanger(solid: true))
                    .controlSize(.large)
                    .disabled(!canDelete)
                }
                .padding()
            }
            .navigationTitle("Supprimer votre compte ?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(running) }
            }
        }
        .interactiveDismissDisabled(running)
    }

    private func delete() {
        guard canDelete, let me else { return }
        running = true
        error = nil
        Task {
            defer { running = false }
            do {
                // Signing in again gives a fresh `auth_time`, which wely-users checks.
                try await app.session.signIn(username: me.email ?? me.userName, password: password)
            } catch {
                self.error = (error as? AuthError) == .invalidCredentials ? "Mot de passe incorrect." : error.localizedDescription
                password = ""
                return
            }
            let outcome: AccountDeletionOutcome
            do {
                try await app.users.deleteAccount()
                outcome = .deleted
            } catch {
                outcome = AccountDeletionOutcome(refusal: error)
            }
            switch outcome {
            case .deleted:
                dismiss()
                await app.session.signOut()
            case .reauthenticationRequired:
                error = "Votre confirmation a expiré : retapez votre mot de passe."
                password = ""
            case .protected:
                error = "Le compte de démonstration ne peut pas être supprimé."
            case .unavailable:
                error = "La suppression du compte est indisponible pour le moment."
            case .failed(let message):
                error = message
            }
        }
    }
}
