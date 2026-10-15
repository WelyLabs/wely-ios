import Foundation

/// `user-service`: the member's own profile, others' public profiles, pictures.
struct UserService {
    let api: APIClient
    private let base = "user-service"

    func me() async throws -> UserProfile { try await api.get("\(base)/profile") }
    func update(_ update: ProfileUpdate) async throws -> UserProfile { try await api.put("\(base)/profile", body: update) }
    func about() async throws -> ProfileAbout { try await api.get("\(base)/profile/about") }
    func saveAbout(_ about: ProfileAbout) async throws -> ProfileAbout { try await api.put("\(base)/profile/about", body: about) }
    func profile(of userId: String) async throws -> FriendProfile { try await api.get("\(base)/users/\(userId)/profile") }

    func uploadPicture(jpeg: Data) async throws -> String? {
        struct Answer: Decodable { let profilePicUrl: String? }
        let answer: Answer = try await api.upload("\(base)/profile/picture", file: UploadFile(fileName: "avatar.jpg", data: jpeg))
        return answer.profilePicUrl
    }

    /// Signed picture URLs by user id; users without a picture are left out.
    func avatars(of userIds: [String]) async throws -> [String: String] {
        guard !userIds.isEmpty else { return [:] }
        let answer: [String: String?] = try await api.post("\(base)/avatars", body: ["userIds": userIds])
        return answer.compactMapValues { $0 }
    }
}

/// `chat-service` over HTTP; the live part goes through `ChatSocket`.
struct ChatService {
    let api: APIClient
    private let base = "chat-service"

    func conversations() async throws -> [ConversationSummary] {
        let lenient: [Lenient<ConversationSummary>] = try await api.get("\(base)/conversations/all")
        return lenient.compactMap(\.value)
    }
    /// Gets or creates the direct conversation with a friend.
    func conversation(with friendId: String) async throws -> Conversation {
        try await api.get("\(base)/conversations", query: ["friendId": friendId])
    }
    func conversation(_ id: String) async throws -> Conversation { try await api.get("\(base)/conversations/\(id)") }
    func eventConversation(_ eventId: String) async throws -> Conversation { try await api.get("\(base)/conversations/events/\(eventId)") }
    func messages(_ conversationId: String, bucket: Int) async throws -> MessageBucket {
        try await api.get("\(base)/conversations/\(conversationId)/loadMessages", query: ["bucketIndex": String(bucket)])
    }
    func presence(_ userId: String) async throws -> Presence { try await api.get("\(base)/presence/\(userId)") }
    func sendPhoto(_ conversationId: String, jpeg: Data, caption: String) async throws -> Message {
        let fields = caption.trimmingCharacters(in: .whitespaces).isEmpty ? [:] : ["caption": caption.trimmingCharacters(in: .whitespaces)]
        return try await api.upload("\(base)/conversations/\(conversationId)/photos", file: UploadFile(data: jpeg), fields: fields)
    }
}

/// `notifications-service`: the notification center and its preferences.
struct NotificationService {
    let api: APIClient
    private let base = "notifications-service"
    static let pageSize = 30

    func page(before: Date? = nil) async throws -> [AppNotification] {
        let lenient: [Lenient<AppNotification>] = try await api.get("\(base)/notifications", query: [
            "limit": String(Self.pageSize), "before": before?.ISO8601Format(.iso8601WithTimeZone(includingFractionalSeconds: true)),
        ])
        return lenient.compactMap(\.value)
    }
    func unreadCount() async throws -> Int {
        let answer: UnreadCount = try await api.get("\(base)/notifications/unread-count")
        return answer.count
    }
    func markRead(_ request: NotificationReadRequest) async throws { try await api.send("POST", "\(base)/notifications/read", body: request) }
    func preferences() async throws -> NotificationPreferences { try await api.get("\(base)/preferences") }
    func savePreferences(_ preferences: NotificationPreferences) async throws { try await api.send("PUT", "\(base)/preferences", body: preferences) }

    var streamURL: URL { api.url("\(base)/notifications/stream") }
}
