import Foundation

/// `social-service`: people, friendships and communities.
struct SocialService {
    let api: APIClient
    private let base = "social-service"

    // MARK: People

    /// Every user with the caller's relation to them; `filter` narrows to one status.
    func users(filter: String? = nil) async throws -> [UserWithStatus] {
        let lenient: [Lenient<UserWithStatus>] = try await api.get("\(base)/users", query: ["friendshipStatus": filter])
        return lenient.compactMap(\.value)
    }
    func friends() async throws -> [UserNode] { try await api.get("\(base)/users", query: ["friendshipStatus": "FRIENDS"]) }
    func person(_ userId: String) async throws -> SocialPerson { try await api.get("\(base)/users/\(userId)") }
    func mutualFriends(_ userId: String) async throws -> [UserNode] { try await api.get("\(base)/users/\(userId)/mutual") }

    // MARK: Friendships

    func friendships() async throws -> [FriendSummary] { try await api.get("\(base)/relationships") }
    func sendRequest(tag: String, viaEventId: String? = nil) async throws -> UserNode {
        try await api.post("\(base)/relationships/request", body: FriendRequest(userTag: tag, viaEventId: viaEventId))
    }
    func accept(_ userId: String) async throws { try await api.send("PUT", "\(base)/relationships/accept/\(userId)") }
    func reject(_ userId: String) async throws { try await api.send("PUT", "\(base)/relationships/reject/\(userId)") }
    func remove(_ userId: String) async throws { try await api.delete("\(base)/relationships/\(userId)") }

    func requestCloseness(_ friendId: String, _ closeness: Closeness) async throws -> Friendship {
        try await api.put("\(base)/relationships/\(friendId)/closeness", body: ClosenessRequest(closeness: closeness))
    }
    func acceptCloseness(_ friendId: String) async throws -> Friendship { try await api.put("\(base)/relationships/\(friendId)/closeness/accept") }
    func declineCloseness(_ friendId: String) async throws -> Friendship { try await api.put("\(base)/relationships/\(friendId)/closeness/decline") }

    // MARK: Communities

    private var communities: String { "\(base)/communities" }

    func explore(query: String? = nil) async throws -> [Community] {
        try await api.get(communities, query: ["q": query?.isEmpty == false ? query : nil])
    }
    func myCommunities() async throws -> [Community] { try await api.get("\(communities)/mine") }
    func community(_ id: String) async throws -> Community { try await api.get("\(communities)/\(id)") }
    func createCommunity(_ request: CommunityRequest) async throws -> Community { try await api.post(communities, body: request) }
    func updateCommunity(_ id: String, _ request: CommunityRequest) async throws -> Community { try await api.put("\(communities)/\(id)", body: request) }
    func deleteCommunity(_ id: String) async throws { try await api.delete("\(communities)/\(id)") }
    func join(_ id: String) async throws -> Community { try await api.post("\(communities)/\(id)/join") }
    func leaveCommunity(_ id: String, deleteIfLast: Bool) async throws -> CommunityLeaveResult {
        try await api.post("\(communities)/\(id)/leave", body: ["deleteIfLast": deleteIfLast])
    }
    func members(_ id: String) async throws -> [CommunityMember] { try await api.get("\(communities)/\(id)/members") }
    func setRole(_ id: String, member: String, role: CommunityRole) async throws {
        try await api.send("PUT", "\(communities)/\(id)/members/\(member)/role", body: ["role": role.rawValue])
    }
    func removeMember(_ id: String, member: String) async throws { try await api.delete("\(communities)/\(id)/members/\(member)") }
    func invite(_ id: String, friendId: String) async throws -> CommunityInvitation {
        try await api.post("\(communities)/\(id)/invitations", body: ["inviteeId": friendId])
    }
    func invitations(_ id: String) async throws -> [CommunityInvitation] { try await api.get("\(communities)/\(id)/invitations") }
    func revokeInvitation(_ id: String, token: String) async throws { try await api.delete("\(communities)/\(id)/invitations/\(token)") }
    func invitation(token: String) async throws -> CommunityInvitation { try await api.get("\(communities)/invitations/\(token)") }
    func acceptInvitation(token: String) async throws -> Community { try await api.post("\(communities)/invitations/\(token)/accept") }
}
