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
        WelyNavigationStack(path: $path) {
            List {
                Section { header }
                if let summary {
                    Section {
                        stats(summary)
                        friendshipYear(summary)
                    } header: { Text("Ton année Wely") }
                    aboutSection
                    if !summary.upcoming.isEmpty { eventsSection("À venir", summary.upcoming) }
                    if !summary.circle.isEmpty { circleSection(summary.circle) }
                    if !summary.places.isEmpty { placesSection(summary.places) }
                    if !summary.balances.isEmpty { balancesSection(summary.balances) }
                    if !summary.memories.isEmpty { eventsSection("Souvenirs", Array(summary.memories.prefix(5))) }
                }
                Section {
                    NavigationLink(value: Route.preferences) {
                        Label("Préférences", systemImage: "gearshape")
                    }
                    NavigationLink(value: Route.notifications) {
                        Label("Notifications", systemImage: "bell")
                    }
                }
                Section {
                    Button("Se déconnecter", role: .destructive) { Task { await app.signOut() } }
                }
            }
            .navigationTitle("Profil")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: Route.preferences) { Image(systemName: "gearshape") }
                        .accessibilityLabel("Préférences")
                }
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
                    Text(me.displayName).font(.wely.title3.bold())
                    Text(me.handle).foregroundStyle(.secondary)
                    if let email = me.email { Text(email).font(.wely.footnote).foregroundStyle(.secondary) }
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
            Text("\(value)").font(.wely.title2.bold()).foregroundStyle(Theme.gradient)
            Text(label).font(.wely.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// The year's friendships: who joined the circle, who got closer, who came along most.
    @ViewBuilder
    private func friendshipYear(_ summary: ProfileSummary) -> some View {
        if !summary.newFriendsThisYear.isEmpty {
            let count = summary.newFriendsThisYear.count
            HStack(spacing: 12) {
                AvatarStack(userIds: summary.newFriendsThisYear.map(\.userId), limit: 4, size: 30)
                Text(count == 1 ? "1 nouvel ami cette année" : "\(count) nouveaux amis cette année")
                    .font(.wely.subheadline.weight(.medium))
            }
            .accessibilityElement(children: .combine)
        }
        ForEach(summary.upgradesThisYear, id: \.self) { upgrade in
            NavigationLink(value: Route.person(upgrade.userId)) {
                HStack(spacing: 12) {
                    AvatarView(userId: upgrade.userId, size: 30)
                    Text(upgrade.label(name: app.people.person(upgrade.userId).name))
                        .font(.wely.subheadline)
                    Spacer(minLength: 0)
                    Text(upgrade.closeness.celebration.emoji)
                }
            }
        }
        if !summary.topFriendsThisYear.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tes compagnons de sortie").font(.wely.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(summary.topFriendsThisYear.prefix(3).enumerated()), id: \.element.userId) { rank, companion in
                        NavigationLink(value: Route.person(companion.userId)) {
                            VStack(spacing: 4) {
                                AvatarView(userId: companion.userId, size: 48)
                                    .overlay(alignment: .bottomTrailing) {
                                        Text(["🥇", "🥈", "🥉"][rank]).font(.system(size: 16)).offset(x: 4, y: 4)
                                    }
                                Text(app.people.person(companion.userId).name).font(.wely.caption).lineLimit(1)
                                Text(companion.outingsTogether == 1 ? "1 sortie" : "\(companion.outingsTogether) sorties")
                                    .font(.wely.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
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
                Button("Modifier") { editingAbout = true }.font(.wely.caption).textCase(nil)
            }
        }
    }

    private func eventsSection(_ title: String, _ events: [FeedEvent]) -> some View {
        Section(title) {
            ForEach(events) { event in
                NavigationLink(value: Route.event(event)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.wely.body.weight(.medium))
                        Text(event.isOpenPoll ? "Date en sondage" : event.startDate.dayLabel()).font(.wely.caption).foregroundStyle(.secondary)
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
                                Text(app.people.person(companion.userId).name).font(.wely.caption).lineLimit(1)
                                Text("\(companion.outingsTogether) sorties").font(.wely.caption2).foregroundStyle(.secondary)
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
    @State private var birthDate: Date
    private let savedBirthDate: String?

    init(profile: UserProfile) {
        _update = State(initialValue: ProfileUpdate(userName: profile.userName, firstName: profile.firstName ?? "", lastName: profile.lastName ?? ""))
        savedBirthDate = profile.birthDate
        _birthDate = State(initialValue: profile.birthDate.flatMap { DayString.date(from: $0, calendar: .wely) } ?? SignupAnswers.initial().birthDate)
    }

    /// The birth date to send, when it differs from the saved one.
    private var changedBirthDate: String? {
        let day = DayString.string(from: birthDate, calendar: .wely)
        return day == savedBirthDate ? nil : day
    }

    var body: some View {
        WelyNavigationStack {
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
                Section {
                    DatePicker("Date de naissance", selection: $birthDate, in: SignupAnswers.birthDateRange(), displayedComponents: .date)
                } footer: { Text("Tes amis verront le jour et le mois, jamais ton année.") }
            }
            .environment(\.locale, .wely)
            .navigationTitle("Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert($failure)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Enregistrer") {
                        var saved = try await app.users.update(update)
                        if let day = changedBirthDate { saved = try await app.users.completeRegistration(birthDate: day) }
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
        WelyNavigationStack {
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

extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
