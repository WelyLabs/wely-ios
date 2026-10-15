import MapKit
import PhotosUI
import SwiftUI

/// The member's own page: who they are, their year in Wely, their circle and places, settings.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var summary: ProfileSummary?
    @State private var about: ProfileAbout?
    @State private var pictureItem: PhotosPickerItem?
    @State private var editing = false
    @State private var editingAbout = false
    @State private var path = NavigationPath()
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section { header }
                if let summary {
                    Section { stats(summary) }
                    aboutSection
                    if !summary.upcoming.isEmpty { eventsSection("À venir", summary.upcoming) }
                    if !summary.circle.isEmpty { circleSection(summary.circle) }
                    if !summary.places.isEmpty { placesSection(summary.places) }
                    if !summary.balances.isEmpty { balancesSection(summary.balances) }
                    if !summary.memories.isEmpty { eventsSection("Souvenirs", Array(summary.memories.prefix(5))) }
                }
                Section("Réglages") {
                    NavigationLink { NotificationPreferencesView() } label: { Label("Notifications", systemImage: "bell") }
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    LabeledContent("Serveur", value: app.session.config.gatewayURL.host() ?? "—")
                    if app.isDemo { LabeledContent("Mode", value: "Démo") }
                }
                Section {
                    Button("Se déconnecter", role: .destructive) { Task { await app.session.signOut() } }
                }
            }
            .navigationTitle("Profil")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier") { editing = true }.disabled(app.people.me == nil)
                }
            }
            .sheet(isPresented: $editing) { if let me = app.people.me { EditProfileView(profile: me) } }
            .sheet(isPresented: $editingAbout) { EditAboutView(about: about ?? ProfileAbout()) { about = $0 } }
            .onChange(of: pictureItem) { _, item in
                guard let item else { return }
                Task { await uploadPicture(item) }
            }
            .withRoutes()
            .handlesDestinations(on: .profile, path: $path)
            .task(id: app.eventsVersion) { await load() }
            .refreshable { await load() }
            .errorAlert($error)
        }
    }

    @ViewBuilder
    private var header: some View {
        if let me = app.people.me {
            HStack(spacing: 16) {
                PhotosPicker(selection: $pictureItem, matching: .images) {
                    AvatarView(userId: me.id, size: 72)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Theme.blue, in: Circle())
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Changer la photo de profil")
                VStack(alignment: .leading, spacing: 4) {
                    Text(me.displayName).font(.title3.bold())
                    Text(me.handle).foregroundStyle(.secondary)
                    if let email = me.email { Text(email).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .padding(.vertical, 6)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func stats(_ summary: ProfileSummary) -> some View {
        HStack {
            stat(summary.outingsThisYear, "sorties\ncette année")
            Divider()
            stat(summary.outingsThisMonth, "ce mois-ci")
            Divider()
            stat(summary.organizedThisYear, "organisées")
            Divider()
            stat(summary.placesThisYear, "lieux")
        }
        .padding(.vertical, 6)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(Theme.gradient)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var aboutSection: some View {
        Section {
            if let about, about.bio?.isEmpty == false || !about.interests.isEmpty {
                if let bio = about.bio, !bio.isEmpty { Text(bio) }
                if !about.interests.isEmpty {
                    FlowLayout { ForEach(about.interests, id: \.self) { TagView(text: $0) } }
                }
            } else {
                Text("Présentez-vous en une phrase et quelques centres d'intérêt.").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("À propos")
                Spacer()
                Button("Modifier") { editingAbout = true }.font(.caption).textCase(nil)
            }
        }
    }

    private func eventsSection(_ title: String, _ events: [FeedEvent]) -> some View {
        Section(title) {
            ForEach(events) { event in
                NavigationLink(value: Route.event(event)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.body.weight(.medium))
                        Text(event.isOpenPoll ? "Date en sondage" : event.startDate.dayLabel()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func circleSection(_ circle: [Companion]) -> some View {
        Section("Mon cercle") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(circle, id: \.userId) { companion in
                        NavigationLink(value: Route.person(companion.userId)) {
                            VStack(spacing: 4) {
                                AvatarView(userId: companion.userId, size: 56)
                                Text(app.people.person(companion.userId).name).font(.caption).lineLimit(1)
                                Text("\(companion.outingsTogether) sorties").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func placesSection(_ places: [VisitedPlace]) -> some View {
        Section("Mes lieux") {
            let located = places.filter { $0.coordinates != nil }
            if !located.isEmpty {
                Map {
                    ForEach(located, id: \.label) { place in
                        Marker(place.label, coordinate: CLLocationCoordinate2D(latitude: place.coordinates!.latitude, longitude: place.coordinates!.longitude))
                            .tint(Theme.orange)
                    }
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())
            }
            ForEach(places, id: \.label) { place in
                LabeledContent(place.label, value: "\(place.visits) fois")
            }
        }
    }

    private func balancesSection(_ balances: [EventBalance]) -> some View {
        Section("Mes comptes") {
            ForEach(balances, id: \.eventId) { balance in
                NavigationLink(value: Route.eventId(balance.eventId)) {
                    LabeledContent(balance.title) {
                        Text((balance.netCents >= 0 ? "+" : "−") + Money.format(cents: abs(balance.netCents)))
                            .foregroundStyle(balance.netCents >= 0 ? .green : .red)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func load() async {
        async let summary = app.events.mySummary()
        async let about = app.users.about()
        self.summary = (try? await summary) ?? self.summary
        self.about = (try? await about) ?? self.about
        if app.people.me == nil { await app.people.loadMe() }
    }

    private func uploadPicture(_ item: PhotosPickerItem) async {
        defer { pictureItem = nil }
        do {
            let jpeg = try await PhotoLoader.jpeg(from: item, maxSide: 800)
            _ = try await app.users.uploadPicture(jpeg: jpeg)
            if let id = app.people.myId { app.people.invalidatePicture(id) }
        } catch { self.error = error.localizedDescription }
    }
}

/// Name and pseudo.
private struct EditProfileView: View {
    @State private var failure: String?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var update: ProfileUpdate

    init(profile: UserProfile) {
        _update = State(initialValue: ProfileUpdate(userName: profile.userName, firstName: profile.firstName ?? "", lastName: profile.lastName ?? ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Prénom", text: $update.firstName).textContentType(.givenName)
                    TextField("Nom", text: $update.lastName).textContentType(.familyName)
                }
                Section {
                    TextField("Pseudo", text: $update.userName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: { Text("Votre tag public devient « pseudo#\(app.people.me?.hashtag ?? "") ».") }
            }
            .navigationTitle("Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert($failure)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Enregistrer") {
                        let saved = try await app.users.update(update)
                        app.people.setMe(saved)
                        dismiss()
                    }
                    .disabled(update.userName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Bio and interests.
private struct EditAboutView: View {
    @State private var failure: String?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var about: ProfileAbout
    let onSaved: (ProfileAbout) -> Void
    @State private var newInterest = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Une phrase sur vous", text: Binding(get: { about.bio ?? "" }, set: { about.bio = String($0.prefix(ProfileAbout.bioMax)) }),
                              axis: .vertical)
                        .lineLimit(2...4)
                } footer: { Text("\((about.bio ?? "").count)/\(ProfileAbout.bioMax)") }
                Section("Centres d'intérêt") {
                    ForEach(about.interests, id: \.self) { Text($0) }
                        .onDelete { about.interests.remove(atOffsets: $0) }
                    if about.interests.count < ProfileAbout.interestsMax {
                        HStack {
                            TextField("Ajouter", text: $newInterest).onSubmit(add)
                            Button("Ajouter", action: add).disabled(newInterest.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("À propos")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert($failure)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Enregistrer") {
                        onSaved(try await app.users.saveAbout(about))
                        dismiss()
                    }
                }
            }
        }
    }

    private func add() {
        let value = String(newInterest.trimmingCharacters(in: .whitespaces).prefix(ProfileAbout.interestMax))
        guard !value.isEmpty, !about.interests.contains(value) else { return }
        about.interests.append(value)
        newInterest = ""
    }
}

/// Which kinds of notification to receive.
private struct NotificationPreferencesView: View {
    @Environment(AppModel.self) private var app
    @State private var preferences: NotificationPreferences?
    @State private var error: String?

    var body: some View {
        Form {
            if let binding = Binding($preferences) {
                Section {
                    Toggle("Appels", isOn: binding.calls)
                    Toggle("Messages", isOn: binding.messages)
                    Toggle("Événements", isOn: binding.events)
                    Toggle("Amis", isOn: binding.friends)
                } footer: {
                    Text("Les notifications désactivées n'apparaissent plus dans le centre de notifications.")
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Notifications")
        .task { preferences = try? await app.notificationService.preferences() }
        .onChange(of: preferences) { old, new in
            guard old != nil, let new else { return }
            Task {
                do { try await app.notificationService.savePreferences(new) } catch { self.error = error.localizedDescription }
            }
        }
        .errorAlert($error)
    }
}

extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
