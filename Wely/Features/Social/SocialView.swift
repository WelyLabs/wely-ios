import SwiftUI

/// Friends and communities.
struct SocialView: View {
    @State private var section = Section.friends
    @State private var path = NavigationPath()

    enum Section { case friends, communities }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch section {
                case .friends: FriendsList()
                case .communities: CommunitiesList()
                }
            }
            .navigationTitle(section == .friends ? "Amis" : "Communautés")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Picker("Section", selection: $section) {
                    Text("Amis").tag(Section.friends)
                    Text("Communautés").tag(Section.communities)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .withRoutes()
            .handlesDestinations(on: .social, path: $path)
        }
    }
}

/// My friends, the requests waiting for me, and everyone else to add.
private struct FriendsList: View {
    @Environment(AppModel.self) private var app
    @State private var friendships: [FriendSummary] = []
    @State private var users: [UserWithStatus] = []
    @State private var query = ""
    @State private var loaded = false
    @State private var addingByTag = false
    @State private var error: String?

    private var incoming: [UserWithStatus] { users.filter { $0.relationStatus.isIncoming } }
    private var outgoing: [UserWithStatus] { users.filter { $0.relationStatus.isOutgoing } }

    private var searchResults: [UserWithStatus] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return users.filter { $0.userName.lowercased().contains(q) || "\($0.userName)#\($0.hashtag)".lowercased().contains(q) }
    }

    var body: some View {
        List {
            if !query.isEmpty {
                Section("Résultats") {
                    if searchResults.isEmpty { Text("Personne ne correspond.").foregroundStyle(.secondary) }
                    ForEach(searchResults) { user in
                        NavigationLink(value: Route.person(user.userId)) {
                            PersonRow(userId: user.userId) { relationButton(user) }
                        }
                    }
                }
            } else {
                if !incoming.isEmpty {
                    Section("Demandes reçues") {
                        ForEach(incoming) { user in
                            NavigationLink(value: Route.person(user.userId)) {
                                PersonRow(userId: user.userId, subtitle: "veut devenir votre ami") {
                                    HStack(spacing: 8) {
                                        AsyncButton { try await app.social.reject(user.userId); await load() } label: {
                                            Image(systemName: "xmark")
                                        }
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("Refuser")
                                        AsyncButton { try await app.social.accept(user.userId); await load() } label: {
                                            Image(systemName: "checkmark")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .accessibilityLabel("Accepter")
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    if friendships.isEmpty, loaded {
                        Text("Pas encore d'amis : ajoutez-les par leur tag ou cherchez-les.").foregroundStyle(.secondary)
                    }
                    ForEach(friendships) { friend in
                        NavigationLink(value: Route.person(friend.userId)) {
                            PersonRow(userId: friend.userId, subtitle: closenessLine(friend)) {
                                if friend.proposal != nil, friend.proposedByFriend {
                                    Image(systemName: "sparkles").foregroundStyle(Theme.orange)
                                        .accessibilityLabel("Proposition de proximité en attente")
                                }
                            }
                        }
                    }
                } header: {
                    Text(friendships.isEmpty ? "Amis" : "Amis (\(friendships.count))")
                }

                if !outgoing.isEmpty {
                    Section("Demandes envoyées") {
                        ForEach(outgoing) { user in
                            PersonRow(userId: user.userId, subtitle: "en attente") {
                                AsyncButton("Annuler") { try await app.social.remove(user.userId); await load() }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Chercher par pseudo ou tag")
        .overlay { if !loaded { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingByTag = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("Ajouter un ami")
            }
        }
        .sheet(isPresented: $addingByTag) { AddFriendSheet { Task { await load() } } }
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($error)
    }

    @ViewBuilder
    private func relationButton(_ user: UserWithStatus) -> some View {
        switch user.relationStatus {
        case .friends:
            Text("Ami").font(.caption).foregroundStyle(.secondary)
        case _ where user.relationStatus.isOutgoing:
            Text("Envoyée").font(.caption).foregroundStyle(.secondary)
        case _ where user.relationStatus.isIncoming:
            AsyncButton("Accepter") { try await app.social.accept(user.userId); await load() }
                .buttonStyle(.borderedProminent).font(.caption)
        case .me:
            EmptyView()
        default:
            AsyncButton {
                _ = try await app.social.sendRequest(tag: "\(user.userName)#\(user.hashtag)")
                await load()
            } label: {
                Image(systemName: "person.badge.plus")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Ajouter \(user.userName)")
        }
    }

    private func closenessLine(_ friend: FriendSummary) -> String {
        if let proposal = friend.proposal {
            return friend.proposedByFriend ? "\(friend.closeness.label) · propose « \(proposal.label) »" : "\(friend.closeness.label) · vous proposez « \(proposal.label) »"
        }
        return friend.closeness.label
    }

    private func load() async {
        do {
            async let friendships = app.social.friendships()
            async let users = app.social.users()
            self.friendships = try await friendships
            self.users = try await users
            app.people.remember(self.users.map(\.person) + self.friendships.map(\.person))
        } catch {
            if !loaded { self.error = error.localizedDescription }
        }
        loaded = true
    }
}

/// Adds a friend by their public tag, and shows mine to share.
private struct AddFriendSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onSent: () -> Void
    @State private var tag = ""
    @State private var sent: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("pseudo#1234", text: $tag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Le tag est affiché sur le profil de votre ami.")
                }
                Section {
                    AsyncButton("Envoyer la demande") {
                        let node = try await app.social.sendRequest(tag: tag.trimmingCharacters(in: .whitespaces))
                        sent = node.userName
                        onSent()
                    }
                    .disabled(!tag.contains("#"))
                }
                if let sent {
                    Label("Demande envoyée à \(sent)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let me = app.people.me {
                    Section("Votre tag") {
                        HStack {
                            Text(me.tag).font(.body.monospaced())
                            Spacer()
                            ShareLink(item: "Ajoute-moi sur Wely : \(me.tag)") { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                }
            }
            .navigationTitle("Ajouter un ami")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
