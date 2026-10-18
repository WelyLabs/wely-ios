import Foundation

struct AppNotification: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let type: String
    let category: String?
    let title: String
    let body: String
    /// A web path: `/event/<id>`, `/chat/<id>`, `/friends/<id>`, `/call/<id>`...
    let link: String?
    let groupKey: String?
    let count: Int?
    let actorId: String?
    let createdAt: Date
    var readAt: Date?

    var isRead: Bool { readAt != nil }

    var systemImage: String {
        switch type {
        case "CALL_INCOMING": "phone.fill"
        case "CALL_MISSED": "phone.arrow.down.left"
        case "MESSAGE": "bubble.left.fill"
        case "EVENT_DATE_FIXED", "EVENT_MOVED": "calendar"
        case "FRIEND_REQUEST": "person.badge.plus"
        case "FRIEND_ACCEPTED": "person.crop.circle.badge.checkmark"
        case "BIRTHDAY_TODAY": "birthday.cake.fill"
        case "FRIEND_BIRTHDAY": "gift.fill"
        case "BIRTHDAY_SURPRISE_PROPOSAL", "BIRTHDAY_SURPRISE_CREATED": "party.popper.fill"
        case "REUNION_NUDGE": "hand.wave.fill"
        case "FRIENDSHIP_ANNIVERSARY": "heart.text.square.fill"
        case "CLOSENESS_UPGRADED": "heart.circle.fill"
        default: "bell.fill"
        }
    }

    /// Where the link points in the app.
    var destination: AppDestination? { link.flatMap(AppDestination.init(webPath:)) }
}

struct NotificationPreferences: Codable, Hashable, Sendable {
    var calls: Bool
    var messages: Bool
    var events: Bool
    var friends: Bool
    /// Missing from a backend that predates it: on, as its default.
    @DefaultTrue var birthdays: Bool = true
}

struct NotificationReadRequest: Codable, Sendable {
    var ids: [String]?
    var groupKey: String?
    var all: Bool?
}

/// Which APNs gateway a device token belongs to: development builds get sandbox tokens.
enum ApnsEnvironment: String, Codable, Sendable {
    case sandbox = "SANDBOX"
    case production = "PRODUCTION"
}

/// An alert token gets notifications; a PushKit (VoIP) token, incoming calls for CallKit.
enum ApnsPushKind: String, Codable, Sendable {
    case alert = "ALERT"
    case voip = "VOIP"
}

struct ApnsDeviceRequest: Codable, Sendable {
    let token: String
    let environment: ApnsEnvironment
    var kind = ApnsPushKind.alert
}

struct UnreadCount: Codable, Sendable {
    let count: Int
}

/// A screen of the app a notification or a shared link can lead to.
enum AppDestination: Hashable, Sendable {
    case event(String)
    case conversation(String)
    case person(String)
    case community(String)
    case invitation(String)
    case preferences
    case call(String)
    /// A day of the calendar, « YYYY-MM-DD ».
    case calendarDay(String)
    /// The pre-filled surprise for a friend's birthday on that day.
    case surprise(honoreeId: String, date: String)
    /// A friend's page with « Proposer une sortie » opened.
    case proposeOuting(friendId: String)
    /// What the user and a friend lived together.
    case memories(friendId: String)

    /// Reads wely-web's paths, so notifications and shared links land on the same screen.
    init?(webPath: String) {
        let path = webPath.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? webPath
        let parts = path.split(separator: "/").map(String.init)
        let query = Self.query(of: webPath)
        switch (parts.first, parts.count) {
        case ("calendar", 1):
            guard let date = query["date"] else { return nil }
            if let honoreeId = query["surpriseFor"], !honoreeId.isEmpty {
                self = .surprise(honoreeId: honoreeId, date: date)
            } else {
                self = .calendarDay(date)
            }
        case ("event", 2...): self = .event(parts.last!)
        case ("chat", 2): self = .conversation(parts[1])
        case ("friends", 2) where query["propose"] == "1": self = .proposeOuting(friendId: parts[1])
        case ("friends", 2): self = .person(parts[1])
        case ("friends", 3) where parts[2] == "memories": self = .memories(friendId: parts[1])
        case ("communities", 3) where parts[1] == "invite": self = .invitation(parts[2])
        case ("communities", 2): self = .community(parts[1])
        case ("preferences", 1): self = .preferences
        case ("call", 2): self = .call(parts[1])
        default: return nil
        }
    }

    private static func query(of webPath: String) -> [String: String] {
        let items = URLComponents(string: webPath)?.queryItems ?? []
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
    }
}
