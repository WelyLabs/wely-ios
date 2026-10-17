import Foundation

/// Who may see an event besides those taking part.
enum Visibility: String, Codable, Sendable, CaseIterable {
    case `public` = "PUBLIC"
    case friends = "FRIENDS"
    case `private` = "PRIVATE"
    case community = "COMMUNITY"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Visibility(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .public: "Public"
        case .friends: "Amis"
        case .private: "Privé"
        case .community: "Communauté"
        case .unknown: "—"
        }
    }

    var systemImage: String {
        switch self {
        case .public: "globe"
        case .friends: "person.2"
        case .private: "lock"
        case .community: "person.3"
        case .unknown: "questionmark"
        }
    }
}

/// What an event is: an ordinary one, someone's yearly birthday, or a surprise kept from its honoree.
enum EventKind: String, Codable, Sendable {
    case standard = "STANDARD"
    case birthday = "BIRTHDAY"
    case surprise = "SURPRISE"

    /// Unknown kinds from a newer backend read as ordinary events.
    init(from decoder: Decoder) throws {
        self = EventKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .standard
    }
}

/// A point on Earth, in decimal degrees.
struct Coordinates: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// A proposed slot of a date poll and who answered what, by user id.
struct PollSlot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let start: Date
    let end: Date
    let yes: [String]
    let maybe: [String]
    let no: [String]

    enum CodingKeys: String, CodingKey { case id, start, end, yes, maybe, no }

    init(id: String, start: Date, end: Date, yes: [String] = [], maybe: [String] = [], no: [String] = []) {
        self.id = id
        self.start = start
        self.end = end
        self.yes = yes
        self.maybe = maybe
        self.no = no
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        yes = try c.decodeIfPresent([String].self, forKey: .yes) ?? []
        maybe = try c.decodeIfPresent([String].self, forKey: .maybe) ?? []
        no = try c.decodeIfPresent([String].self, forKey: .no) ?? []
    }
}

/// A date poll: open while people vote, closed once the organizer fixed a slot.
struct Poll: Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable { case open = "OPEN", closed = "CLOSED" }

    let status: Status
    let fixedSlotId: String?
    let slots: [PollSlot]

    enum CodingKeys: String, CodingKey { case status, fixedSlotId, slots }

    init(status: Status, fixedSlotId: String? = nil, slots: [PollSlot]) {
        self.status = status
        self.fixedSlotId = fixedSlotId
        self.slots = slots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Status.self, forKey: .status)
        fixedSlotId = try c.decodeIfPresent(String.self, forKey: .fixedSlotId)
        // A slot with unreadable dates is dropped rather than failing the whole event.
        slots = (try c.decodeIfPresent([Lenient<PollSlot>].self, forKey: .slots) ?? []).compactMap(\.value)
    }

    var isOpen: Bool { status == .open }
}

/// An event as `wely-events` sends it (`/events/me/subscribed`, `/events/{id}`, ...).
struct FeedEvent: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let organizerId: String
    let startDate: Date
    let endDate: Date
    let location: String
    let coordinates: Coordinates?
    /// The cover: a signed URL, a `/demo/...` path, or nil.
    let image: String?
    let description: String
    let visibility: Visibility?
    let poll: Poll?
    let communityId: String?
    /// Who answered what, for a community event only.
    let responses: EventResponses?
    /// Whole days, from 00:00Z of the first to 00:00Z of the day after the last.
    let allDay: Bool
    let kind: EventKind
    /// Whose birthday it is, for a birthday or a surprise.
    let honoreeId: String?

    /// Without an end, an event lasts an hour, as the server counts it.
    static let defaultDuration: TimeInterval = 3600

    enum CodingKeys: String, CodingKey {
        case id, title, organizerId, startDate, endDate, location, coordinates, image, description, visibility, poll, communityId, responses
        case allDay, kind, honoreeId
    }

    init(
        id: String, title: String, organizerId: String, startDate: Date, endDate: Date? = nil,
        location: String = "", coordinates: Coordinates? = nil, image: String? = nil, description: String = "",
        visibility: Visibility? = .friends, poll: Poll? = nil, communityId: String? = nil, responses: EventResponses? = nil,
        allDay: Bool = false, kind: EventKind = .standard, honoreeId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.organizerId = organizerId
        self.startDate = startDate
        self.endDate = endDate ?? startDate.addingTimeInterval(Self.defaultDuration)
        self.location = location
        self.coordinates = coordinates
        self.image = image
        self.description = description
        self.visibility = visibility
        self.poll = poll
        self.communityId = communityId
        self.responses = responses
        self.allDay = allDay
        self.kind = kind
        self.honoreeId = honoreeId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        organizerId = try c.decodeIfPresent(String.self, forKey: .organizerId) ?? ""
        startDate = (try? c.decodeIfPresent(Date.self, forKey: .startDate)) ?? .now
        endDate = (try? c.decodeIfPresent(Date.self, forKey: .endDate)) ?? startDate.addingTimeInterval(Self.defaultDuration)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        coordinates = try? c.decodeIfPresent(Coordinates.self, forKey: .coordinates)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        visibility = try c.decodeIfPresent(Visibility.self, forKey: .visibility)
        poll = try? c.decodeIfPresent(Poll.self, forKey: .poll)
        communityId = try c.decodeIfPresent(String.self, forKey: .communityId)
        responses = try? c.decodeIfPresent(EventResponses.self, forKey: .responses)
        allDay = (try? c.decodeIfPresent(Bool.self, forKey: .allDay)) ?? false
        kind = (try? c.decodeIfPresent(EventKind.self, forKey: .kind)) ?? .standard
        honoreeId = try? c.decodeIfPresent(String.self, forKey: .honoreeId)
    }

    var isOpenPoll: Bool { poll?.isOpen == true }
    var isPast: Bool { endDate < .now }
    /// A birthday is everyone's to see, no one's to join.
    var isJoinable: Bool { kind != .birthday }

    /// The choices offered when creating an event; COMMUNITY is set by the backend.
    static let choosableVisibilities: [Visibility] = [.friends, .public, .private]
}

extension FeedEvent {
    /// A copy with some fields replaced.
    func with(start: Date? = nil, end: Date? = nil, poll: Poll?? = nil, responses: EventResponses?? = nil, image: String?? = nil) -> FeedEvent {
        FeedEvent(id: id, title: title, organizerId: organizerId, startDate: start ?? startDate, endDate: end ?? endDate, location: location,
                  coordinates: coordinates, image: image ?? self.image, description: description, visibility: visibility,
                  poll: poll ?? self.poll, communityId: communityId, responses: responses ?? self.responses,
                  allDay: allDay, kind: kind, honoreeId: honoreeId)
    }
}
