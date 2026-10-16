import PhotosUI
import SwiftUI

/// One conversation: its messages, live, and the composer.
struct ChatView: View {
    enum Target: Hashable {
        case conversation(String)
        case friend(String)
        case event(String, title: String)
    }

    @Environment(AppModel.self) private var app
    let target: Target

    @State private var conversation: Conversation?
    @State private var messages: [Message] = []
    @State private var oldestBucket = 0
    @State private var presence: Presence?
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var loadError: String?
    @State private var error: String?
    @State private var viewingPhoto: URL?

    private var myId: String? { app.people.myId }
    private var otherId: String? {
        guard conversation?.type == .direct else { return nil }
        return conversation?.participantIds.first { $0 != myId }
    }

    var body: some View {
        Group {
            if conversation != nil {
                messageList
            } else if let loadError {
                EmptyStateView(title: "Conversation indisponible", systemImage: "bubble.left.and.exclamationmark.bubble.right", message: loadError)
            } else {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .bottom) { if conversation != nil { composer } }
        .navigationBarTitleDisplayMode(.inline)
        .hidesWelyTabBar()
        .toolbar {
            ToolbarItem(placement: .principal) { titleView }
        }
        .task { await load() }
        .task(id: conversation?.id) {
            guard let id = conversation?.id else { return }
            for await message in app.chatSocket.messages() where message.conversationId == id { upsert(message) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
        .sheet(item: $viewingPhoto) { url in PhotoViewer(url: url) }
        .errorAlert($error)
    }

    // MARK: Pieces

    private var titleView: some View {
        VStack(spacing: 0) {
            switch target {
            case .event(_, let title):
                Text(title).font(.wely.headline).lineLimit(1)
                Text("Fil du groupe").font(.wely.caption2).foregroundStyle(.secondary)
            default:
                if let otherId {
                    NavigationLink(value: Route.person(otherId)) {
                        VStack(spacing: 0) {
                            Text(app.people.person(otherId).name).font(.wely.headline)
                            if let presence {
                                Text(presence.online ? "En ligne" : presence.lastSeenAt.map { "Vu \($0.relativeShort().lowercased())" } ?? "")
                                    .font(.wely.caption2)
                                    .foregroundStyle(presence.online ? .green : .secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(conversation?.title ?? "Groupe").font(.wely.headline).lineLimit(1)
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if oldestBucket > 0 {
                        AsyncButton("Messages précédents") { try await loadOlder() }
                            .font(.wely.caption)
                            .padding(.vertical, 8)
                    }
                    if messages.isEmpty {
                        Text("Personne n'a encore écrit. Lancez la discussion !")
                            .font(.wely.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || !Calendar.wely.isDate(messages[index - 1].timestamp, inSameDayAs: message.timestamp) {
                            Text(message.timestamp.dayLabel())
                                .font(.wely.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 10)
                        }
                        MessageBubble(
                            message: message,
                            mine: message.senderId == myId,
                            showAuthor: conversation?.type != .direct && message.senderId != myId
                                && (index == 0 || messages[index - 1].senderId != message.senderId),
                            onPhoto: { viewingPhoto = $0 },
                            onRetry: { Task { await resend(message) } }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.wely.title3)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Envoyer une photo")
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Envoyer")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Loading

    private func load() async {
        do {
            let conversation: Conversation = switch target {
            case .conversation(let id): try await app.chat.conversation(id)
            case .friend(let friendId): try await app.chat.conversation(with: friendId)
            case .event(let eventId, _): try await app.chat.eventConversation(eventId)
            }
            self.conversation = conversation
            messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }
            oldestBucket = conversation.bucketIndex ?? 0
            loadError = nil
            if let otherId { presence = try? await app.chat.presence(otherId) }
        } catch let failure as APIError where failure.status == 403 {
            loadError = "Le fil du groupe est réservé aux participants."
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadOlder() async throws {
        guard let id = conversation?.id, oldestBucket > 0 else { return }
        let bucket = try await app.chat.messages(id, bucket: oldestBucket - 1)
        oldestBucket = bucket.bucketIndex
        let known = Set(messages.map(\.id))
        messages = (bucket.messages.filter { !known.contains($0.id) } + messages).sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: Sending

    private func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let conversation, let myId else { return }
        draft = ""
        let pending = Message(id: "pending-\(UUID().uuidString)", senderId: myId, senderName: app.people.me?.userName, receiverId: otherId,
                              conversationId: conversation.id, content: content, timestamp: .now, pending: true)
        messages.append(pending)
        await deliver(pending)
    }

    private func resend(_ message: Message) async {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].failed = false
        messages[index].pending = true
        await deliver(messages[index])
    }

    private func deliver(_ pending: Message) async {
        guard let conversation else { return }
        do {
            let stored = try await app.chatSocket.send(ChatInput(receiverId: otherId ?? "", conversationId: conversation.id, content: pending.content))
            guard let index = messages.firstIndex(where: { $0.id == pending.id }) else { return }
            messages[index].pending = false
            if let stored {
                messages[index].timestamp = stored.timestamp
                if !stored.id.hasPrefix("local-"), !messages.contains(where: { $0.id == stored.id }) { messages[index].id = stored.id }
            }
        } catch {
            guard let index = messages.firstIndex(where: { $0.id == pending.id }) else { return }
            messages[index].pending = false
            messages[index].failed = true
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let conversation else { return }
        do {
            let jpeg = try await PhotoLoader.jpeg(from: item, maxSide: 2048)
            let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            draft = ""
            upsert(try await app.chat.sendPhoto(conversation.id, jpeg: jpeg, caption: caption))
        } catch { self.error = error.localizedDescription }
    }

    /// A pushed message: an update replaces it, my own echo replaces its local copy (the ack
    /// carries no id), anything else is appended.
    private func upsert(_ message: Message) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else if message.senderId == myId, message.photo == nil,
                  let index = messages.firstIndex(where: { $0.id.hasPrefix("pending-") && $0.content == message.content }) {
            messages[index] = message
        } else {
            messages.append(message)
            messages.sort { $0.timestamp < $1.timestamp }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct MessageBubble: View {
    @Environment(AppModel.self) private var app
    let message: Message
    let mine: Bool
    let showAuthor: Bool
    let onPhoto: (URL) -> Void
    let onRetry: () -> Void

    var body: some View {
        if message.isSystem {
            Text(message.content)
                .font(.wely.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .bottom, spacing: 6) {
                if mine { Spacer(minLength: 48) }
                if !mine, showAuthor { AvatarView(userId: message.senderId, size: 26) } else if !mine { Color.clear.frame(width: 26) }
                VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                    if showAuthor {
                        Text(app.people.person(message.senderId).name).font(.wely.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if let photo = message.photo {
                        photoView(photo)
                    }
                    if !message.content.isEmpty {
                        Text(message.content)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(mine ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Color(.secondarySystemBackground)),
                                        in: RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(mine ? .white : .primary)
                            .opacity(message.pending ? 0.6 : 1)
                    }
                    HStack(spacing: 4) {
                        if message.failed {
                            Button(action: onRetry) {
                                Label("Non envoyé · Réessayer", systemImage: "exclamationmark.circle").font(.wely.caption2)
                            }
                            .foregroundStyle(.red)
                        } else {
                            Text(message.pending ? "Envoi…" : message.timestamp.formatted(.dateTime.hour().minute().locale(.wely)))
                                .font(.wely.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let reactions = message.reactions, !reactions.isEmpty {
                            Text(reactions.map { "\($0.key) \($0.value)" }.joined(separator: " ")).font(.wely.caption2)
                        }
                    }
                }
                if !mine { Spacer(minLength: 48) }
            }
        }
    }

    @ViewBuilder
    private func photoView(_ photo: MessagePhoto) -> some View {
        if photo.removed {
            Label("Photo retirée", systemImage: "photo").font(.wely.caption).foregroundStyle(.secondary)
                .padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        } else if let raw = photo.url, let url = AppConfig.current.imageURL(raw) {
            let ratio = photo.height > 0 ? CGFloat(photo.width) / CGFloat(photo.height) : 1
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.secondarySystemBackground)
            }
            .frame(width: 220, height: 220 / max(0.5, min(ratio, 2)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { onPhoto(url) }
        }
    }
}

/// A photo full screen, pinch to zoom.
private struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var scale: CGFloat = 1

    var body: some View {
        WelyNavigationStack {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit().scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation { scale = 1 } })
            } placeholder: { ProgressView() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
            }
        }
    }
}
