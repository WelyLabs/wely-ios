import SwiftUI

/// Someone's profile: who they are, where we stand, what we share and what they have planned.
struct PersonView: View {
    @Environment(AppModel.self) private var app
    let userId: String

    @State private var person: SocialPerson?
    @State private var profile: FriendProfile?
    @State private var overview: FriendOverview?
    @State private var mutual: [UserNode] = []
    @State private var loadError: String?
    @State private var showingCalendar = false
    @State private var confirmingRemoval = false
    @State private var error: String?

    private var isFriend: Bool { person?.relationStatus == .friends }

    var body: some View {
        ScrollView {
            if let person {
                VStack(spacing: 20) {
                    header(person)
                    actions(person)
                    if isFriend { closeness(person) }
                    if let profile, (profile.bio?.isEmpty == false || !profile.interests.isEmpty) { about(profile) }
                    if let overview { shared(overview) }
                    if !mutual.isEmpty { mutualFriends }
                }
                .padding()
            } else if let loadError {
                ContentUnavailableView("Profil introuvable", systemImage: "person.crop.circle.badge.questionmark", description: Text(loadError))
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isFriend {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmingRemoval = true } label: { Label("Retirer des amis", systemImage: "person.badge.minus") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .confirmationDialog("Retirer \(person?.userName ?? "") de vos amis ?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Retirer", role: .destructive) {
                Task {
                    do { try await app.social.remove(userId); await load() } catch { self.error = error.localizedDescription }
                }
            }
        }
        .sheet(isPresented: $showingCalendar) { FriendCalendarSheet(userId: userId) }
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($error)
    }

    private func header(_ person: SocialPerson) -> some View {
        VStack(spacing: 8) {
            AvatarView(userId: userId, size: 96)
            Text(profile?.displayName ?? person.userName).font(.title2.bold())
            Text(person.person.handle).foregroundStyle(.secondary)
            if let since = person.since, isFriend, let date = WireDate.parse(since) ?? WireDate.parse(since + "T00:00:00") {
                Text("Amis depuis \(date.formatted(.dateTime.month(.wide).year().locale(.wely)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actions(_ person: SocialPerson) -> some View {
        HStack(spacing: 12) {
            switch person.relationStatus {
            case .friends:
                NavigationLink(value: Route.directChat(friendId: userId)) {
                    Label("Message", systemImage: "bubble.left.fill").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                Button { showingCalendar = true } label: {
                    Label("Agenda", systemImage: "calendar").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
            case let status where status.isIncoming:
                AsyncButton { try await app.social.accept(userId); await load() } label: {
                    Label("Accepter", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                AsyncButton(role: .destructive) { try await app.social.reject(userId); await load() } label: {
                    Text("Refuser").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
            case let status where status.isOutgoing:
                Label("Demande envoyée", systemImage: "clock").foregroundStyle(.secondary)
                AsyncButton("Annuler") { try await app.social.remove(userId); await load() }.buttonStyle(.bordered)
            case .me:
                EmptyView()
            default:
                AsyncButton {
                    _ = try await app.social.sendRequest(tag: "\(person.userName)#\(person.hashtag)")
                    await load()
                } label: {
                    Label("Ajouter en ami", systemImage: "person.badge.plus").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func closeness(_ person: SocialPerson) -> some View {
        let friendship = Friendship(friendId: userId, closeness: person.closeness ?? .friend, proposal: person.proposal, proposedByFriend: person.proposedByFriend)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(friendship.closeness.label, systemImage: "heart.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.orange)
                    Spacer()
                    Menu {
                        ForEach(friendship.options, id: \.closeness) { option in
                            Button(option.label) { Task { await change(to: option.closeness) } }
                        }
                    } label: {
                        Text("Changer").font(.subheadline.weight(.medium))
                    }
                }
                Text("\(person.userName) \(friendship.closeness.hint).").font(.caption).foregroundStyle(.secondary)
                if let proposal = friendship.proposal {
                    if friendship.proposedByFriend {
                        Text("\(person.userName) propose de passer à « \(proposal.label) » : \(proposal.hint).")
                            .font(.subheadline)
                        HStack {
                            AsyncButton("Accepter") { _ = try await app.social.acceptCloseness(userId); await load() }
                                .buttonStyle(.borderedProminent)
                            AsyncButton("Refuser") { _ = try await app.social.declineCloseness(userId); await load() }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Text("Vous avez proposé « \(proposal.label) », en attente.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func about(_ profile: FriendProfile) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if let bio = profile.bio, !bio.isEmpty { Text(bio) }
                if !profile.interests.isEmpty {
                    FlowLayout { ForEach(profile.interests, id: \.self) { TagView(text: $0) } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func shared(_ overview: FriendOverview) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(overview.outingsTogether)").font(.title.bold())
                    Text(overview.outingsTogether == 1 ? "sortie ensemble" : "sorties ensemble").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "figure.2").font(.largeTitle).foregroundStyle(Theme.gradient)
            }
        }
        eventList("Bientôt ensemble", overview.upcomingTogether)
        eventList("Ses prochaines sorties", overview.friendUpcoming)
        eventList("Souvenirs communs", overview.memoriesTogether)
    }

    @ViewBuilder
    private func eventList(_ title: String, _ events: [FeedEvent]) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(events) { event in
                    NavigationLink(value: Route.event(event)) { CompactEventRow(event: event) }
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mutualFriends: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amis en commun (\(mutual.count))").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(mutual) { friend in
                        NavigationLink(value: Route.person(friend.userId)) {
                            VStack {
                                AvatarView(userId: friend.userId, size: 52)
                                Text(friend.userName).font(.caption).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func change(to closeness: Closeness) async {
        do {
            _ = try await app.social.requestCloseness(userId, closeness)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func load() async {
        do {
            let person = try await app.social.person(userId)
            self.person = person
            app.people.remember([person.person])
            loadError = nil
            async let profile = app.users.profile(of: userId)
            async let mutual = app.social.mutualFriends(userId)
            self.profile = try? await profile
            self.mutual = (try? await mutual) ?? []
            app.people.remember(self.mutual.map(\.person))
            overview = person.relationStatus == .friends ? try? await app.events.friendOverview(userId) : nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// A rounded panel on the grouped background.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// One line per event: date tile, title, place.
struct CompactEventRow: View {
    let event: FeedEvent

    var body: some View {
        HStack(spacing: 12) {
            DateBadge(date: event.startDate, tentative: event.isOpenPoll)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(event.isOpenPoll ? "Date en sondage" : Date.timeRange(event.startDate, event.endDate))
                    .font(.caption).foregroundStyle(.secondary)
                if !event.location.isEmpty {
                    Text(event.location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A friend's next four weeks, as much as the friendship discloses.
private struct FriendCalendarSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let userId: String
    @State private var state: Loadable<[FriendCalendarEntry]> = .loading

    var body: some View {
        NavigationStack {
            LoadableView(state: state) { entries in
                if entries.isEmpty {
                    ContentUnavailableView("Agenda libre", systemImage: "calendar", description: Text("Rien de prévu dans les 4 prochaines semaines."))
                } else {
                    List(entries, id: \.self) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title ?? "Occupé").font(.body.weight(entry.title == nil ? .regular : .semibold))
                                .foregroundStyle(entry.title == nil ? .secondary : .primary)
                            Text("\(entry.start.dayLabel()) · \(Date.timeRange(entry.start, entry.end))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let location = entry.location, !location.isEmpty {
                                Text(location).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agenda de \(app.people.name(userId))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .task {
                do {
                    let entries = try await app.events.friendCalendar(userId, from: .now, to: .now.addingTimeInterval(28 * 86_400))
                    state = .loaded(entries.sorted { $0.start < $1.start })
                } catch { state = .failed(error.localizedDescription) }
            }
        }
    }
}
