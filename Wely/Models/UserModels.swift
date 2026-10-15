import Foundation

/// The signed-in member, from `user-service/profile`.
struct UserProfile: Codable, Hashable, Sendable {
    let id: String
    let userName: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let profilePicUrl: String?
    @LossyString var hashtag: String = ""
    let bio: String?
    let joinedDate: String?

    init(id: String, userName: String, email: String? = nil, firstName: String? = nil, lastName: String? = nil,
         profilePicUrl: String? = nil, hashtag: String = "", bio: String? = nil, joinedDate: String? = nil) {
        self.id = id
        self.userName = userName
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.profilePicUrl = profilePicUrl
        self.hashtag = hashtag
        self.bio = bio
        self.joinedDate = joinedDate
    }

    var displayName: String {
        let full = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? userName : full
    }

    var handle: String { Person.handle(userName: userName, hashtag: hashtag) }

    var initials: String {
        let letters = [firstName, lastName].compactMap { $0?.first }.map(String.init)
        return letters.isEmpty ? String(userName.prefix(2)).uppercased() : letters.joined().uppercased()
    }

    /// The public tag friends type to add you: `robin#4907`.
    var tag: String { hashtag.isEmpty ? userName : "\(userName)#\(hashtag)" }
}

/// `PUT user-service/profile`.
struct ProfileUpdate: Codable, Sendable {
    var userName: String
    var firstName: String
    var lastName: String
}

/// The member's short bio and interests, `user-service/profile/about`.
struct ProfileAbout: Codable, Hashable, Sendable {
    var bio: String?
    @DefaultEmpty var interests: [String] = []

    init(bio: String? = nil, interests: [String] = []) {
        self.bio = bio
        self.interests = interests
    }

    static let bioMax = 160
    static let interestsMax = 5
    static let interestMax = 24
}

/// Another member's public profile, `user-service/users/{id}/profile`.
struct FriendProfile: Codable, Hashable, Sendable {
    let id: String
    let userName: String
    @LossyString var hashtag: String = ""
    let firstName: String?
    let lastName: String?
    let joinedDate: String?
    let bio: String?
    @DefaultEmpty var interests: [String] = []

    var displayName: String {
        let full = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? userName : full
    }
}

/// Anyone shown on a screen: enough for an avatar and a name.
struct Person: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    var hashtag: String = ""
    var pictureURL: String?

    var handle: String { Self.handle(userName: name, hashtag: hashtag) }

    static func handle(userName: String, hashtag: String) -> String {
        hashtag.isEmpty ? "@\(userName)" : "@\(userName)#\(hashtag)"
    }

    /// Two letters: first and last name, or the first two letters of a single name.
    static func initials(of name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        let letters = parts.count > 1 ? "\(parts[0].prefix(1))\(parts[1].prefix(1))" : String((parts.first ?? "?").prefix(2))
        return letters.uppercased()
    }
}
