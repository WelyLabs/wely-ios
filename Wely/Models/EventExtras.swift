import Foundation

/// A member's answer to a poll slot or to a community event.
enum PollAnswer: String, Codable, CaseIterable, Sendable {
    case yes = "YES"
    case maybe = "MAYBE"
    case no = "NO"

    var label: String {
        switch self {
        case .yes: "Oui"
        case .maybe: "Peut-être"
        case .no: "Non"
        }
    }
}

/// Who answered what to a community event, by user id.
struct EventResponses: Codable, Hashable, Sendable {
    @DefaultEmpty var yes: [String] = []
    @DefaultEmpty var maybe: [String] = []
    @DefaultEmpty var no: [String] = []

    init(yes: [String] = [], maybe: [String] = [], no: [String] = []) {
        self.yes = yes
        self.maybe = maybe
        self.no = no
    }

    func answer(of userId: String) -> PollAnswer? {
        if yes.contains(userId) { return .yes }
        if maybe.contains(userId) { return .maybe }
        if no.contains(userId) { return .no }
        return nil
    }
}

struct EventParticipants: Codable, Hashable, Sendable {
    let count: Int
    @DefaultEmpty var participantIds: [String] = []
    @DefaultEmpty var friendsGoingIds: [String] = []
}

struct EventCreateRequest: Codable, Sendable {
    var title: String
    var startDate: Date
    var endDate: Date?
    var location: String
    var coordinates: Coordinates?
    var description: String?
    var visibility: Visibility?
    var candidateSlots: [Slot]?
    var communityId: String?
    var allDay: Bool?
    var kind: EventKind?
    var honoreeId: String?

    struct Slot: Codable, Hashable, Sendable {
        var start: Date
        var end: Date
    }
}

/// `PUT /events/{id}`: what the organizer may rewrite; the date moves through `/schedule`.
struct EventUpdateRequest: Codable, Sendable {
    var title: String
    var location: String
    var coordinates: Coordinates?
    var description: String?
    /// Nil keeps the current one; ignored on a community event.
    var visibility: Visibility?
}

struct LeaveChoice: Codable, Sendable {
    var newOrganizerId: String?
    var deleteIfLast: Bool?
}

struct LeaveResult: Codable, Sendable {
    @DefaultFalse var deleted: Bool = false
    let event: FeedEvent?
}

struct BallotRequest: Codable, Sendable {
    let answers: [String: PollAnswer]
}

struct SlotChoice: Codable, Sendable {
    let slotId: String
}

struct AnswerRequest: Codable, Sendable {
    let answer: PollAnswer
}

struct ConflictsRequest: Codable, Sendable {
    let start: Date
    let end: Date
    var excludedEventId: String?
}

struct FreeSlotSearch: Codable, Sendable {
    let friendIds: [String]
    let start: Date
    let end: Date
    let durationMinutes: Int
}

struct FreeRange: Codable, Hashable, Sendable {
    let start: Date
    let end: Date
}

/// One event of a friend's calendar, as much as the friendship discloses.
struct FriendCalendarEntry: Codable, Hashable, Sendable {
    let start: Date
    let end: Date
    let eventId: String?
    let title: String?
    let location: String?
    let description: String?
}

struct Companion: Codable, Hashable, Sendable {
    let userId: String
    let outingsTogether: Int
}

struct VisitedPlace: Codable, Hashable, Sendable {
    let label: String
    let coordinates: Coordinates?
    let visits: Int
}

struct EventBalance: Codable, Hashable, Sendable {
    let eventId: String
    let title: String
    let netCents: Int
}

/// The member's life in Wely, `events/me/summary`.
struct ProfileSummary: Codable, Hashable, Sendable {
    let outingsThisYear: Int
    let outingsThisMonth: Int
    let organizedThisYear: Int
    let placesThisYear: Int
    @DefaultEmpty var upcoming: [FeedEvent] = []
    @DefaultEmpty var memories: [FeedEvent] = []
    let pastCount: Int?
    @DefaultEmpty var circle: [Companion] = []
    @DefaultEmpty var places: [VisitedPlace] = []
    @DefaultEmpty var balances: [EventBalance] = []
    /// The year in review's friendships; empty from a backend that predates them.
    @DefaultEmpty var newFriendsThisYear: [NewFriend] = []
    @DefaultEmpty var upgradesThisYear: [ClosenessUpgrade] = []
    @DefaultEmpty var topFriendsThisYear: [Companion] = []

    var hasFriendshipYear: Bool { !newFriendsThisYear.isEmpty || !upgradesThisYear.isEmpty || !topFriendsThisYear.isEmpty }
}

/// What the viewer and a friend share, `events/users/{id}/overview`.
struct FriendOverview: Codable, Hashable, Sendable {
    let outingsTogether: Int
    @DefaultEmpty var upcomingTogether: [FeedEvent] = []
    @DefaultEmpty var memoriesTogether: [FeedEvent] = []
    @DefaultEmpty var friendUpcoming: [FeedEvent] = []
}
