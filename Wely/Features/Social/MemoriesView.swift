import SwiftUI

/// « 1 an d'amitié avec Léa »: how long, how many outings, the first and the last, the best ones.
struct MemoriesView: View {
    @Environment(AppModel.self) private var app
    let friendId: String
    @State private var state: Loadable<FriendshipMemories> = .loading

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            switch state {
            case .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                EmptyStateView(title: "Souvenirs indisponibles", systemImage: "heart.slash", message: message)
            case .loaded(let memories):
                VStack(spacing: 20) {
                    hero(memories)
                    stats(memories)
                    if memories.first != nil || memories.last != nil { milestones(memories) }
                    if !memories.highlights.isEmpty { highlights(memories.highlights) }
                    if memories.sharedCount == 0 {
                        Text("Pas encore de sortie ensemble sur Wely. La première est à un clic.")
                            .font(.wely.subheadline)
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Vos souvenirs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func hero(_ memories: FriendshipMemories) -> some View {
        let anniversary = memories.isAnniversary()
        return VStack(spacing: 10) {
            HStack(spacing: -14) {
                if let me = app.people.myId {
                    AvatarView(userId: me, size: 64).overlay(Circle().stroke(.white, lineWidth: 3))
                }
                AvatarView(userId: friendId, size: 64).overlay(Circle().stroke(.white, lineWidth: 3))
            }
            if anniversary {
                Text("Joyeux anniversaire d'amitié ! 💛").font(.wely.subheadline.weight(.semibold)).opacity(0.95)
            }
            Text(memories.title)
                .font(.wely.title2.bold())
                .multilineTextAlignment(.center)
            if let since = memories.sinceLabel {
                Text(since).font(.wely.subheadline).opacity(0.9)
            }
            if let closeness = memories.closeness {
                Text(closeness.label)
                    .font(.wely.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.22), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            // A gentle celebration on the day itself; ConfettiView keeps still under reduced motion.
            if anniversary { ConfettiView().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).allowsHitTesting(false) }
        }
        .shadow(color: Theme.orange.opacity(anniversary ? 0.3 : 0.15), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
    }

    private func stats(_ memories: FriendshipMemories) -> some View {
        HStack {
            stat("\(memories.sharedCount)", memories.sharedCount == 1 ? "sortie ensemble" : "sorties ensemble")
            Divider().frame(height: 36)
            stat("\(memories.days)", memories.days == 1 ? "jour d'amitié" : "jours d'amitié")
        }
        .padding(.vertical, 12)
        .welyCard(radius: 16)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.wely.title2.bold()).foregroundStyle(Theme.gradient)
            Text(label).font(.wely.caption).foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
    }

    private func milestones(_ memories: FriendshipMemories) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let first = memories.first { milestone("Première sortie", first) }
            if let last = memories.last, last != memories.first { milestone("Dernière sortie", last) }
        }
    }

    private func milestone(_ label: String, _ event: MemoryEvent) -> some View {
        NavigationLink(value: Route.eventId(event.eventId)) {
            HStack(spacing: 12) {
                if let date = event.startDate { DateBadge(date: date, tentative: false) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.wely.caption.weight(.semibold)).foregroundStyle(Theme.ink2).textCase(.uppercase)
                    Text(event.title).font(.wely.body.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.wely.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func highlights(_ events: [MemoryEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Moments forts").font(.wely.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(events) { event in
                    NavigationLink(value: Route.eventId(event.eventId)) { HighlightTile(event: event) }
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        do {
            state = .loaded(try await app.events.memories(with: friendId))
        } catch let error as APIError where error.status == 404 {
            state = .failed("Ces souvenirs ne se partagent qu'entre amis.")
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }
}

/// A shared outing as a tile: its cover or colours, title and date.
private struct HighlightTile: View {
    let event: MemoryEvent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = AppConfig.current.imageURL(event.imageUrl) {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                        EventTint.gradient(for: event.eventId).opacity(0.4)
                    }
                } else {
                    EventTint.gradient(for: event.eventId)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: EventTint.symbol(for: event.title))
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(10)
                        }
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.wely.subheadline.weight(.semibold)).lineLimit(2)
                if let date = event.startDate {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year().locale(.wely))).font(.wely.caption2).opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
