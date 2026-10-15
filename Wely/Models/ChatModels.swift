import Foundation

enum ConversationType: String, Codable, Sendable {
    case direct = "DIRECT"
    case group = "GROUP"
    case event = "EVENT"
    case unknown

    init(from decoder: Decoder) throws {
        self = ConversationType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

enum MessageType: String, Codable, Sendable {
    case text = "TEXT"
    case image = "IMAGE"
    case video = "VIDEO"
    case system = "SYSTEM"
    case unknown

    init(from decoder: Decoder) throws {
        self = MessageType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

struct MessagePhoto: Codable, Hashable, Sendable {
    let width: Int
    let height: Int
    let url: String?
    @DefaultFalse var removed: Bool = false
}

struct Message: Codable, Hashable, Identifiable, Sendable {
    var id: String
    let senderId: String
    let senderName: String?
    let receiverId: String?
    let conversationId: String
    let content: String
    let type: MessageType?
    var timestamp: Date
    let reactions: [String: Int]?
    let photo: MessagePhoto?
    /// NEW or UPDATED, on the live stream.
    let kind: String?

    /// Local state of a message being sent: not on the wire.
    var pending = false
    var failed = false

    enum CodingKeys: String, CodingKey {
        case id, senderId, senderName, receiverId, conversationId, content, type, timestamp, reactions, photo, kind
    }

    init(id: String, senderId: String, senderName: String?, receiverId: String?, conversationId: String, content: String,
         type: MessageType? = .text, timestamp: Date, reactions: [String: Int]? = nil, photo: MessagePhoto? = nil,
         kind: String? = nil, pending: Bool = false) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.receiverId = receiverId
        self.conversationId = conversationId
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.reactions = reactions
        self.photo = photo
        self.kind = kind
        self.pending = pending
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The server's ack carries no id yet: a local one keeps it apart.
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "local-\(UUID().uuidString)"
        senderId = try c.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName)
        receiverId = try c.decodeIfPresent(String.self, forKey: .receiverId)
        conversationId = try c.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        type = try c.decodeIfPresent(MessageType.self, forKey: .type)
        timestamp = (try? c.decodeIfPresent(Date.self, forKey: .timestamp)) ?? .now
        reactions = try? c.decodeIfPresent([String: Int].self, forKey: .reactions)
        photo = try? c.decodeIfPresent(MessagePhoto.self, forKey: .photo)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
    }

    var isSystem: Bool { type == .system }

    /// A one-line preview for the conversations list.
    var preview: String {
        if photo != nil { return content.isEmpty ? "📷 Photo" : "📷 \(content)" }
        return content
    }
}

struct Conversation: Codable, Hashable, Identifiable, Sendable {
    let id: String
    @DefaultEmpty var participantIds: [String] = []
    let type: ConversationType
    let title: String?
    let eventId: String?
    let organizerId: String?
    let updatedAt: Date?
    let lastMessage: Message?
    @DefaultEmpty var messages: [Message] = []
    let bucketIndex: Int?
}

struct ConversationSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    @DefaultEmpty var participantIds: [String] = []
    let type: ConversationType
    let title: String?
    let updatedAt: Date?
    let lastMessage: Message?
    let lastBucketIndex: Int?
    let eventId: String?
}

struct MessageBucket: Codable, Sendable {
    let conversationId: String
    let bucketIndex: Int
    @DefaultEmpty var messages: [Message] = []
}

struct Presence: Codable, Hashable, Sendable {
    let userId: String
    @DefaultFalse var online: Bool = false
    let lastSeenAt: Date?
}

/// What `chat.send` takes over RSocket.
struct ChatInput: Codable, Sendable {
    let receiverId: String
    let conversationId: String
    let content: String
}
