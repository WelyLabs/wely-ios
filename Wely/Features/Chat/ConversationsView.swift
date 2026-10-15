import SwiftUI

/// Every conversation, most recent first; a new message moves its conversation up live.
struct ConversationsView: View {
    @Environment(AppModel.self) private var app
    @State private var conversations: [ConversationSummary] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var path = NavigationPath()
    @State private var startingChat = false

    var body: some View {
        NavigationStack(path: $path) {
            List(conversations) { conversation in
                NavigationLink(value: Route.conversation(conversation.id)) {
                    ConversationRow(conversation: conversation)
                }
            }
            .listStyle(.plain)
            .overlay {
                if !loaded {
                    ProgressView()
                } else if let loadError, conversations.isEmpty {
                    ContentUnavailableView("Messagerie indisponible", systemImage: "bubble.left.and.exclamationmark.bubble.right", description: Text(loadError))
                } else if conversations.isEmpty {
                    ContentUnavailableView("Aucune conversation", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Écrivez à un ami depuis son profil, ou discutez dans le fil d'un événement."))
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startingChat = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Nouveau message")
                }
            }
            .sheet(isPresented: $startingChat) {
                FriendPicker(title: "Nouveau message") { friendId in path.append(Route.directChat(friendId: friendId)) }
            }
            .withRoutes()
            .handlesDestinations(on: .messages, path: $path)
            .task { await load() }
            .refreshable { await load() }
            .task {
                for await message in app.chatSocket.messages() { receive(message) }
            }
        }
    }

    private func load() async {
        do {
            conversations = try await app.chat.conversations()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        loaded = true
    }

    private func receive(_ message: Message) {
        guard let index = conversations.firstIndex(where: { $0.id == message.conversationId }) else {
            Task { await load() }
            return
        }
        let old = conversations.remove(at: index)
        conversations.insert(ConversationSummary(id: old.id, participantIds: old.participantIds, type: old.type, title: old.title,
                                                 updatedAt: message.timestamp, lastMessage: message, lastBucketIndex: old.lastBucketIndex,
                                                 eventId: old.eventId), at: 0)
    }
}

private struct ConversationRow: View {
    @Environment(AppModel.self) private var app
    let conversation: ConversationSummary

    private var others: [String] { conversation.participantIds.filter { $0 != app.people.myId } }

    var body: some View {
        HStack(spacing: 12) {
            if conversation.type == .direct, let other = others.first {
                AvatarView(userId: other, size: 48)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(EventTint.gradient(for: conversation.eventId ?? conversation.id))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: conversation.type == .event ? EventTint.symbol(for: conversation.title ?? "") : "person.3.fill")
                            .foregroundStyle(.white)
                    }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if let date = conversation.updatedAt {
                        Text(date.relativeShort()).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        if conversation.type == .direct, let other = others.first { return app.people.person(other).name }
        return conversation.title?.isEmpty == false ? conversation.title! : others.map { app.people.name($0) }.joined(separator: ", ")
    }

    private var preview: String {
        guard let message = conversation.lastMessage else { return "Aucun message" }
        if message.isSystem { return message.content }
        let author = message.senderId == app.people.myId ? "Vous : " : (conversation.type == .direct ? "" : "\(app.people.name(message.senderId)) : ")
        return author + message.preview
    }
}

/// Picks one friend.
struct FriendPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onPick: (String) -> Void
    @State private var friends: [UserNode] = []
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(friends.filter { query.isEmpty || $0.userName.localizedCaseInsensitiveContains(query) }) { friend in
                Button {
                    dismiss()
                    onPick(friend.userId)
                } label: {
                    PersonRow(userId: friend.userId)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .task {
                friends = (try? await app.social.friends()) ?? []
                app.people.remember(friends.map(\.person))
            }
        }
    }
}
