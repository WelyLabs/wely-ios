import Foundation

enum CommunityVisibility: String, Codable, CaseIterable, Sendable {
    case `public` = "PUBLIC"
    case `private` = "PRIVATE"

    var label: String { self == .public ? "Publique" : "Privée" }
    var systemImage: String { self == .public ? "globe" : "lock" }
}

enum CommunityRole: String, Codable, Sendable {
    case admin = "ADMIN"
    case member = "MEMBER"

    var label: String { self == .admin ? "Admin" : "Membre" }
}

struct Community: Codable, Hashable, Identifiable, Sendable {
    let communityId: String
    let name: String
    let description: String?
    @DefaultEmpty var interests: [String] = []
    let visibility: CommunityVisibility
    let createdAt: Date?
    let memberCount: Int
    /// The caller's role; nil when not a member.
    let role: CommunityRole?
    @DefaultEmpty var friendMembers: [UserNode] = []
    let friendMemberCount: Int?

    var id: String { communityId }
    var isMember: Bool { role != nil }
    var isAdmin: Bool { role == .admin }

    static let nameRange = 3...60
    static let descriptionMax = 500
    static let interestsMax = 5
}

struct CommunityRequest: Codable, Sendable {
    var name: String
    var description: String?
    var interests: [String]
    var visibility: CommunityVisibility
}

struct CommunityMember: Codable, Hashable, Identifiable, Sendable {
    let userId: String
    let userName: String
    @LossyString var hashtag: String = ""
    let profilePicUrl: String?
    let role: CommunityRole
    let joinedAt: Date?

    var id: String { userId }
    var person: Person { Person(id: userId, name: userName, hashtag: hashtag, pictureURL: profilePicUrl) }
}

struct CommunityInvitation: Codable, Hashable, Identifiable, Sendable {
    let token: String
    let communityId: String
    let communityName: String
    let visibility: CommunityVisibility
    let inviterId: String
    let inviterName: String?
    let inviteeId: String
    let inviteeName: String?
    let createdAt: Date?
    let expiresAt: Date?
    @DefaultFalse var expired: Bool = false

    var id: String { token }

    /// The token in a shared link `…/communities/invite/<token>`.
    static func token(in text: String?) -> String? {
        guard let text, let range = text.range(of: #"/communities/invite/([A-Za-z0-9_-]{16,})"#, options: .regularExpression) else { return nil }
        return String(text[range].split(separator: "/").last!)
    }
}

struct CommunityLeaveResult: Codable, Sendable {
    @DefaultFalse var communityDeleted: Bool = false
    let newAdminId: String?
}
