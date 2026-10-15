import Foundation

/// How close two friends are; each level discloses more of one's calendar.
enum Closeness: String, Codable, CaseIterable, Sendable, Comparable {
    case friend = "FRIEND"
    case close = "CLOSE"
    case intimate = "INTIMATE"

    var label: String {
        switch self {
        case .friend: "Ami"
        case .close: "Proche"
        case .intimate: "Intime"
        }
    }

    var hint: String {
        switch self {
        case .friend: "voit quand vous êtes occupé"
        case .close: "voit aussi le titre de vos événements"
        case .intimate: "voit tout le détail de vos événements"
        }
    }

    static func < (lhs: Closeness, rhs: Closeness) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Where the caller stands with someone.
enum RelationStatus: String, Codable, Sendable {
    case me = "SELF"
    case none = "NONE"
    case friends = "FRIENDS"
    case sentByMe = "SENT_BY_ME"
    case sentByThem = "SENT_BY_THEM"
    case pendingIncoming = "PENDING_INCOMING"
    case pendingOutgoing = "PENDING_OUTGOING"
    case unknown

    init(from decoder: Decoder) throws {
        self = RelationStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// Both spellings of « they asked me ».
    var isIncoming: Bool { self == .sentByThem || self == .pendingIncoming }
    /// Both spellings of « I asked them ».
    var isOutgoing: Bool { self == .sentByMe || self == .pendingOutgoing }
}

/// A user node of the social graph.
struct UserNode: Codable, Hashable, Identifiable, Sendable {
    let userId: String
    let userName: String
    @LossyString var hashtag: String = ""
    let profilePicUrl: String?

    var id: String { userId }
    var person: Person { Person(id: userId, name: userName, hashtag: hashtag, pictureURL: profilePicUrl) }
}

/// A user and the caller's relation to them, `social-service/users`.
struct UserWithStatus: Codable, Hashable, Identifiable, Sendable {
    let userId: String
    let userName: String
    let profilePicUrl: String?
    let relationStatus: RelationStatus
    @LossyString var hashtag: String = ""
    let viaEventId: String?

    var id: String { userId }
    var person: Person { Person(id: userId, name: userName, hashtag: hashtag, pictureURL: profilePicUrl) }
}

/// One of my friends, with the friendship's closeness, `social-service/relationships`.
struct FriendSummary: Codable, Hashable, Identifiable, Sendable {
    let userId: String
    let userName: String
    @LossyString var hashtag: String = ""
    let profilePicUrl: String?
    let closeness: Closeness
    let proposal: Closeness?
    @DefaultFalse var proposedByFriend: Bool = false

    var id: String { userId }
    var person: Person { Person(id: userId, name: userName, hashtag: hashtag, pictureURL: profilePicUrl) }
    var friendship: Friendship { Friendship(friendId: userId, closeness: closeness, proposal: proposal, proposedByFriend: proposedByFriend) }
}

struct Friendship: Codable, Hashable, Sendable {
    let friendId: String
    let closeness: Closeness
    let proposal: Closeness?
    @DefaultFalse var proposedByFriend: Bool = false

    /// The levels one may pick: up is a proposal, down is immediate.
    var options: [(closeness: Closeness, label: String)] {
        let ownProposal = proposedByFriend ? nil : proposal
        return Closeness.allCases
            .filter { $0 != closeness && $0 != ownProposal }
            .map { ($0, $0 > closeness ? "Proposer : \($0.label)" : "Redescendre à \($0.label)") }
    }
}

/// Another user and where the caller stands with them, `social-service/users/{id}`.
struct SocialPerson: Codable, Hashable, Sendable {
    let userId: String
    let userName: String
    @LossyString var hashtag: String = ""
    let profilePicUrl: String?
    let relationStatus: RelationStatus
    let closeness: Closeness?
    let proposal: Closeness?
    @DefaultFalse var proposedByFriend: Bool = false
    let since: String?

    var person: Person { Person(id: userId, name: userName, hashtag: hashtag, pictureURL: profilePicUrl) }
}

struct FriendRequest: Codable, Sendable {
    let userTag: String
    var viaEventId: String?
}

struct ClosenessRequest: Codable, Sendable {
    let closeness: Closeness
}
