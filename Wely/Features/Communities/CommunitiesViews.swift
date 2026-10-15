import SwiftUI

/// My communities, and public ones to discover.
struct CommunitiesList: View {
    @Environment(AppModel.self) private var app
    @State private var mine: [Community] = []
    @State private var discover: [Community] = []
    @State private var query = ""
    @State private var loaded = false
    @State private var creating = false
    @State private var joiningByLink = false

    var body: some View {
        List {
            if query.isEmpty {
                Section("Mes communautés") {
                    if mine.isEmpty, loaded {
                        Text("Vous n'êtes membre d'aucune communauté.").foregroundStyle(.secondary)
                    }
                    ForEach(mine) { community in
                        NavigationLink(value: Route.community(community.communityId)) { CommunityRow(community: community) }
                    }
                }
            }
            Section(query.isEmpty ? "À découvrir" : "Résultats") {
                let others = discover.filter { !$0.isMember }
                if others.isEmpty, loaded { Text("Aucune communauté publique à proposer.").foregroundStyle(.secondary) }
                ForEach(others) { community in
                    NavigationLink(value: Route.community(community.communityId)) { CommunityRow(community: community) }
                }
            }
        }
        .searchable(text: $query, prompt: "Chercher une communauté")
        .overlay { if !loaded { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { creating = true } label: { Label("Créer une communauté", systemImage: "plus") }
                    Button { joiningByLink = true } label: { Label("J'ai un lien d'invitation", systemImage: "link") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $creating) { CommunityFormView(existing: nil) { _ in Task { await load() } } }
        .sheet(isPresented: $joiningByLink) { InvitationLinkSheet() }
        .task { await load() }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            if let found = try? await app.social.explore(query: query) { discover = found }
        }
        .refreshable { await load() }
    }

    private func load() async {
        async let mine = app.social.myCommunities()
        async let discover = app.social.explore(query: query)
        self.mine = (try? await mine) ?? self.mine
        self.discover = (try? await discover) ?? self.discover
        loaded = true
    }
}

struct CommunityRow: View {
    let community: Community

    var body: some View {
        HStack(spacing: 12) {
            CommunityBadge(community: community, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(community.name).font(.body.weight(.semibold)).lineLimit(1)
                    if community.visibility == .private { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        var parts = ["\(community.memberCount) membre\(community.memberCount > 1 ? "s" : "")"]
        if let friends = community.friendMemberCount, friends > 0 { parts.append("\(friends) ami\(friends > 1 ? "s" : "")") }
        if community.isAdmin { parts.append("Admin") }
        return parts.joined(separator: " · ")
    }
}

/// A community's initials on its colour.
struct CommunityBadge: View {
    let community: Community
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28)
            .fill(EventTint.gradient(for: community.communityId))
            .frame(width: size, height: size)
            .overlay {
                Text(Person.initials(of: community.name))
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}

/// A community: what it is, its events, its members; joining, leaving, inviting, running it.
struct CommunityDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let communityId: String

    @State private var community: Community?
    @State private var events: [FeedEvent] = []
    @State private var members: [CommunityMember] = []
    @State private var invitations: [CommunityInvitation] = []
    @State private var loadError: String?
    @State private var creatingEvent = false
    @State private var editing = false
    @State private var inviting = false
    @State private var confirmingLeave = false
    @State private var confirmingDelete = false
    @State private var error: String?

    var body: some View {
        Group {
            if let community {
                List {
                    Section { header(community) }
                    if community.isMember {
                        eventsSection
                        membersSection(community)
                        if community.isAdmin, !invitations.isEmpty { invitationsSection }
                    } else if community.visibility == .private {
                        Section { Text("Réservé aux membres : rejoignez la communauté pour voir son contenu.").foregroundStyle(.secondary) }
                    }
                }
            } else if let loadError {
                ContentUnavailableView("Communauté introuvable", systemImage: "person.3", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(community?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if community?.isMember == true { menu } }
        .sheet(isPresented: $creatingEvent) {
            EventFormView(communityId: communityId) { _ in
                app.eventsChanged()
                Task { await load() }
            }
        }
        .sheet(isPresented: $editing) {
            if let community { CommunityFormView(existing: community) { updated in self.community = updated } }
        }
        .sheet(isPresented: $inviting) { InviteFriendsSheet(communityId: communityId, members: Set(members.map(\.userId))) { Task { await load() } } }
        .confirmationDialog("Quitter la communauté ?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Quitter", role: .destructive) { Task { await leave(deleteIfLast: false) } }
        }
        .confirmationDialog("Supprimer la communauté ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Supprimer pour tous", role: .destructive) {
                Task {
                    do { try await app.social.deleteCommunity(communityId); dismiss() } catch { self.error = error.localizedDescription }
                }
            }
        } message: { Text("Ses événements et ses membres seront retirés. C'est définitif.") }
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($error)
    }

    private func header(_ community: Community) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                CommunityBadge(community: community, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(community.name).font(.title3.bold())
                    Label("\(community.visibility.label) · \(community.memberCount) membre\(community.memberCount > 1 ? "s" : "")",
                          systemImage: community.visibility.systemImage)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let description = community.description, !description.isEmpty { Text(description) }
            if !community.interests.isEmpty {
                FlowLayout { ForEach(community.interests, id: \.self) { TagView(text: $0) } }
            }
            if !community.friendMembers.isEmpty {
                HStack {
                    AvatarStack(userIds: community.friendMembers.map(\.userId), size: 24)
                    Text("\(community.friendMembers.map(\.userName).prefix(2).joined(separator: ", ")) en font partie")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !community.isMember {
                AsyncButton {
                    self.community = try await app.social.join(communityId)
                    await load()
                } label: {
                    Text(community.visibility == .private ? "Sur invitation uniquement" : "Rejoindre").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(community.visibility == .private)
            }
        }
        .padding(.vertical, 4)
    }

    private var eventsSection: some View {
        Section {
            if events.isEmpty { Text("Aucun événement à venir.").foregroundStyle(.secondary) }
            ForEach(events) { event in
                NavigationLink(value: Route.event(event)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.body.weight(.medium))
                        Text(event.isOpenPoll ? "Date en sondage" : Date.eventWhen(event.startDate, event.endDate))
                            .font(.caption).foregroundStyle(.secondary)
                        if let responses = event.responses {
                            Text("\(responses.yes.count) oui · \(responses.maybe.count) peut-être").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button { creatingEvent = true } label: { Label("Publier un événement", systemImage: "calendar.badge.plus") }
        } header: { Text("Événements") }
    }

    private func membersSection(_ community: Community) -> some View {
        Section {
            ForEach(members) { member in
                NavigationLink(value: Route.person(member.userId)) {
                    PersonRow(userId: member.userId, subtitle: member.role.label)
                }
                .swipeActions {
                    if community.isAdmin, member.userId != app.people.myId {
                        Button(role: .destructive) { Task { await remove(member) } } label: { Label("Retirer", systemImage: "person.badge.minus") }
                        Button { Task { await toggleAdmin(member) } } label: {
                            Label(member.role == .admin ? "Rétrograder" : "Nommer admin", systemImage: "crown")
                        }
                        .tint(Theme.orange)
                    }
                }
            }
            // Inviting is the admins' call, as on the web and in wely-social.
            if community.isAdmin {
                Button { inviting = true } label: { Label("Inviter des amis", systemImage: "person.badge.plus") }
            }
        } header: { Text("Membres (\(members.count))") } footer: {
            if community.isAdmin { Text("Balayez un membre pour le nommer admin ou le retirer.") }
        }
    }

    private var invitationsSection: some View {
        Section("Invitations en attente") {
            ForEach(invitations) { invitation in
                PersonRow(userId: invitation.inviteeId, subtitle: invitation.expired ? "expirée" : "expire \(invitation.expiresAt?.relativeShort() ?? "")") {
                    AsyncButton("Révoquer", role: .destructive) {
                        try await app.social.revokeInvitation(communityId, token: invitation.token)
                        await load()
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if community?.isAdmin == true {
                    Button { editing = true } label: { Label("Modifier", systemImage: "pencil") }
                }
                Button { confirmingLeave = true } label: { Label("Quitter", systemImage: "rectangle.portrait.and.arrow.right") }
                if community?.isAdmin == true {
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Supprimer", systemImage: "trash") }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private func load() async {
        do {
            let community = try await app.social.community(communityId)
            self.community = community
            loadError = nil
            guard community.isMember else { return }
            async let events = app.events.community(communityId)
            async let members = app.social.members(communityId)
            self.events = (try? await events) ?? []
            self.members = (try? await members) ?? []
            app.people.remember(self.members.map(\.person))
            invitations = community.isAdmin ? (try? await app.social.invitations(communityId)) ?? [] : []
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func leave(deleteIfLast: Bool) async {
        do {
            _ = try await app.social.leaveCommunity(communityId, deleteIfLast: deleteIfLast)
            dismiss()
        } catch let failure as APIError where failure.code == "SCL-BUS-016" {
            await leave(deleteIfLast: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ member: CommunityMember) async {
        do { try await app.social.removeMember(communityId, member: member.userId); await load() } catch { self.error = error.localizedDescription }
    }

    private func toggleAdmin(_ member: CommunityMember) async {
        do {
            try await app.social.setRole(communityId, member: member.userId, role: member.role == .admin ? .member : .admin)
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

/// Creates or edits a community.
struct CommunityFormView: View {
    @State private var failure: String?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let existing: Community?
    let onSaved: (Community) -> Void

    @State private var name = ""
    @State private var details = ""
    @State private var interests: [String] = []
    @State private var newInterest = ""
    @State private var visibility = CommunityVisibility.public

    private var isValid: Bool {
        Community.nameRange.contains(name.trimmingCharacters(in: .whitespaces).count) && details.count <= Community.descriptionMax
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $name)
                    TextField("Description", text: $details, axis: .vertical).lineLimit(3...6)
                } footer: { Text("3 à 60 caractères pour le nom, 500 au plus pour la description.") }
                Section("Centres d'intérêt") {
                    ForEach(interests, id: \.self) { Text($0) }
                        .onDelete { interests.remove(atOffsets: $0) }
                    if interests.count < Community.interestsMax {
                        HStack {
                            TextField("Ajouter (ex. Randonnée)", text: $newInterest)
                                .onSubmit(addInterest)
                            Button("Ajouter", action: addInterest).disabled(newInterest.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                Section {
                    Picker("Visibilité", selection: $visibility) {
                        ForEach(CommunityVisibility.allCases, id: \.self) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    }
                } footer: {
                    Text(visibility == .public ? "Tout le monde peut la trouver et la rejoindre." : "Visible et accessible sur invitation uniquement.")
                }
            }
            .navigationTitle(existing == nil ? "Nouvelle communauté" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert($failure)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton(existing == nil ? "Créer" : "Enregistrer") {
                        let request = CommunityRequest(name: name.trimmingCharacters(in: .whitespaces), description: details.isEmpty ? nil : details,
                                                       interests: interests, visibility: visibility)
                        let saved = if let existing { try await app.social.updateCommunity(existing.communityId, request) }
                                    else { try await app.social.createCommunity(request) }
                        onSaved(saved)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                guard let existing else { return }
                name = existing.name
                details = existing.description ?? ""
                interests = existing.interests
                visibility = existing.visibility
            }
        }
    }

    private func addInterest() {
        let value = newInterest.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !interests.contains(value), interests.count < Community.interestsMax else { return }
        interests.append(String(value.prefix(30)))
        newInterest = ""
    }
}

/// Invites friends who are not members yet; each gets a link valid three days.
private struct InviteFriendsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let communityId: String
    let members: Set<String>
    let onInvited: () -> Void
    @State private var friends: [UserNode] = []
    @State private var invited: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                let candidates = friends.filter { !members.contains($0.userId) }
                if candidates.isEmpty { Text("Tous vos amis sont déjà membres.").foregroundStyle(.secondary) }
                ForEach(candidates) { friend in
                    PersonRow(userId: friend.userId) {
                        if invited.contains(friend.userId) {
                            Label("Invité", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                        } else {
                            AsyncButton("Inviter") {
                                _ = try await app.social.invite(communityId, friendId: friend.userId)
                                invited.insert(friend.userId)
                                onInvited()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Inviter des amis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .task {
                friends = (try? await app.social.friends()) ?? []
                app.people.remember(friends.map(\.person))
            }
        }
    }
}

/// Pastes a shared invitation link to open it.
private struct InvitationLinkSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Lien d'invitation", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Ouvrir l'invitation") {
                    if let token = CommunityInvitation.token(in: link) {
                        dismiss()
                        app.open(.invitation(token))
                    }
                }
                .disabled(CommunityInvitation.token(in: link) == nil)
            }
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// An invitation to a community, to accept.
struct InvitationView: View {
    @Environment(AppModel.self) private var app
    let token: String
    @State private var invitation: CommunityInvitation?
    @State private var joined: Community?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let joined {
                ContentUnavailableView {
                    Label("Bienvenue dans \(joined.name) !", systemImage: "party.popper")
                } actions: {
                    NavigationLink("Voir la communauté", value: Route.community(joined.communityId)).buttonStyle(.borderedProminent)
                }
            } else if let invitation {
                ContentUnavailableView {
                    Label(invitation.communityName, systemImage: "envelope.open")
                } description: {
                    Text(invitation.expired
                         ? "Cette invitation a expiré : demandez-en une nouvelle à un administrateur."
                         : "\(invitation.inviterName ?? "Un membre") vous invite à rejoindre cette communauté.")
                } actions: {
                    if !invitation.expired {
                        AsyncButton("Rejoindre") { joined = try await app.social.acceptInvitation(token: token) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else if let loadError {
                ContentUnavailableView("Invitation invalide", systemImage: "envelope.badge.shield.half.filled", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Invitation")
        .task {
            do { invitation = try await app.social.invitation(token: token) } catch { loadError = error.localizedDescription }
        }
    }
}
