import Foundation

/// A friend not seen for a while, from `events-service/events/me/reunions`.
struct ReunionCandidate: Codable, Hashable, Identifiable, Sendable {
    let friendId: String
    let name: String
    let closeness: Closeness?
    let lastSharedAt: Date?
    let lastSharedEventId: String?
    let lastSharedTitle: String?
    let monthsApart: Int?

    var id: String { friendId }

    enum CodingKeys: String, CodingKey { case friendId, name, closeness, lastSharedAt, lastSharedEventId, lastSharedTitle, monthsApart }

    init(friendId: String, name: String, closeness: Closeness? = nil, lastSharedAt: Date? = nil, lastSharedEventId: String? = nil,
         lastSharedTitle: String? = nil, monthsApart: Int? = nil) {
        self.friendId = friendId
        self.name = name
        self.closeness = closeness
        self.lastSharedAt = lastSharedAt
        self.lastSharedEventId = lastSharedEventId
        self.lastSharedTitle = lastSharedTitle
        self.monthsApart = monthsApart
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        friendId = try c.decode(String.self, forKey: .friendId)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Un ami"
        closeness = try? c.decodeIfPresent(Closeness.self, forKey: .closeness)
        lastSharedAt = try? c.decodeIfPresent(Date.self, forKey: .lastSharedAt)
        lastSharedEventId = try? c.decodeIfPresent(String.self, forKey: .lastSharedEventId)
        lastSharedTitle = try? c.decodeIfPresent(String.self, forKey: .lastSharedTitle)
        monthsApart = try? c.decodeIfPresent(Int.self, forKey: .monthsApart)
    }

    /// « Pas vus depuis 4 mois · Brunch du dimanche », or why there is nothing to count.
    var subtitle: String {
        guard lastSharedAt != nil || lastSharedTitle != nil || monthsApart != nil else {
            return "Aucune sortie partagée sur Wely"
        }
        let since = monthsApart.map { $0 >= 2 ? "Pas vus depuis \($0) mois" : "Pas vus depuis un moment" } ?? "Pas vus depuis un moment"
        guard let title = lastSharedTitle, !title.isEmpty else { return since }
        return "\(since) · \(title)"
    }
}

/// One shared outing in a friendship's memories.
struct MemoryEvent: Codable, Hashable, Identifiable, Sendable {
    let eventId: String
    let title: String
    let startDate: Date?
    /// A signed cover, or nil.
    let imageUrl: String?

    var id: String { eventId }

    enum CodingKeys: String, CodingKey { case eventId, title, startDate, imageUrl }

    init(eventId: String, title: String, startDate: Date?, imageUrl: String? = nil) {
        self.eventId = eventId
        self.title = title
        self.startDate = startDate
        self.imageUrl = imageUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decode(String.self, forKey: .eventId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        startDate = try? c.decodeIfPresent(Date.self, forKey: .startDate)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
    }
}

/// What two friends lived together, `events-service/events/me/friendships/{id}/memories`.
struct FriendshipMemories: Codable, Hashable, Sendable {
    let friendId: String
    let name: String
    let closeness: Closeness?
    let since: Date?
    let years: Int
    let days: Int
    let sharedCount: Int
    let first: MemoryEvent?
    let last: MemoryEvent?
    let highlights: [MemoryEvent]

    enum CodingKeys: String, CodingKey { case friendId, name, closeness, since, years, days, sharedCount, first, last, highlights }

    init(friendId: String, name: String, closeness: Closeness? = nil, since: Date? = nil, years: Int = 0, days: Int = 0,
         sharedCount: Int = 0, first: MemoryEvent? = nil, last: MemoryEvent? = nil, highlights: [MemoryEvent] = []) {
        self.friendId = friendId
        self.name = name
        self.closeness = closeness
        self.since = since
        self.years = years
        self.days = days
        self.sharedCount = sharedCount
        self.first = first
        self.last = last
        self.highlights = highlights
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        friendId = try c.decode(String.self, forKey: .friendId)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Un ami"
        closeness = try? c.decodeIfPresent(Closeness.self, forKey: .closeness)
        since = try? c.decodeIfPresent(Date.self, forKey: .since)
        years = (try? c.decodeIfPresent(Int.self, forKey: .years)) ?? 0
        days = (try? c.decodeIfPresent(Int.self, forKey: .days)) ?? 0
        sharedCount = (try? c.decodeIfPresent(Int.self, forKey: .sharedCount)) ?? 0
        first = try? c.decodeIfPresent(MemoryEvent.self, forKey: .first)
        last = try? c.decodeIfPresent(MemoryEvent.self, forKey: .last)
        highlights = ((try? c.decodeIfPresent([Lenient<MemoryEvent>].self, forKey: .highlights)) ?? []).compactMap(\.value)
    }

    /// « 1 an d'amitié avec Léa », or the days before the first year.
    var title: String {
        if years >= 1 { return "\(years) \(years > 1 ? "ans" : "an") d'amitié avec \(name)" }
        return "\(days) \(days > 1 ? "jours" : "jour") d'amitié avec \(name)"
    }

    /// « depuis le 3 mars 2025 ».
    var sinceLabel: String? {
        since.map { "depuis le \($0.formatted(.dateTime.day().month(.wide).year().locale(.wely)))" }
    }

    /// « 14 sorties ensemble ».
    var sharedLabel: String { sharedCount == 1 ? "1 sortie ensemble" : "\(sharedCount) sorties ensemble" }

    /// Today is the day they became friends, a year or more ago.
    func isAnniversary(today: Date = .now, calendar: Calendar = .wely) -> Bool {
        guard years >= 1, let since else { return false }
        let a = calendar.dateComponents([.month, .day], from: since)
        let b = calendar.dateComponents([.month, .day], from: today)
        return a.month == b.month && a.day == b.day
    }
}

/// A friend among those going to an event, with the caller's closeness to them.
struct FriendGoing: Codable, Hashable, Sendable {
    let userId: String
    let closeness: Closeness?

    enum CodingKeys: String, CodingKey { case userId, closeness }

    init(userId: String, closeness: Closeness?) {
        self.userId = userId
        self.closeness = closeness
    }

    /// An unknown level reads as a plain friend rather than dropping the face.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        closeness = try? c.decodeIfPresent(Closeness.self, forKey: .closeness)
    }
}

/// « 3 de tes proches y vont », or « 7 amis y vont » when no close friend goes.
enum FriendsGoing {
    /// The close and intimate friends among those sent, closest first.
    static func close(_ going: [FriendGoing]) -> [FriendGoing] {
        going.filter { ($0.closeness ?? .friend) >= .close }.sorted { ($0.closeness ?? .friend) > ($1.closeness ?? .friend) }
    }

    static func label(_ going: [FriendGoing], total: Int) -> String? {
        let close = close(going).count
        if close > 0 { return close == 1 ? "1 de tes proches y va" : "\(close) de tes proches y vont" }
        let count = max(total, going.count)
        guard count > 0 else { return nil }
        return count == 1 ? "1 ami y va" : "\(count) amis y vont"
    }

    /// The faces shown next to the label: the close friends when there are, else every friend sent.
    static func faces(_ going: [FriendGoing]) -> [String] {
        let close = close(going)
        return (close.isEmpty ? going : close).map(\.userId)
    }
}

/// The Explore feed with `rank=affinity`: events with friends first, by tier, then the rest by day.
enum FeedRanking {
    struct Section: Hashable, Sendable {
        let title: String
        let events: [FeedEvent]
    }

    static func tierTitle(_ affinity: Int) -> String {
        switch affinity {
        case 3...: "💝 Avec tes intimes"
        case 2: "🧡 Avec tes proches"
        default: "Avec tes amis"
        }
    }

    /// Tiers keep the server's order (affinity, then date); unranked events are grouped by day.
    static func sections(_ events: [FeedEvent], now: Date = .now) -> [Section] {
        let ranked = events.enumerated().sorted { a, b in
            a.element.affinity != b.element.affinity ? a.element.affinity > b.element.affinity : a.offset < b.offset
        }.map(\.element)
        var result: [Section] = []
        for tier in [3, 2, 1] {
            let items = ranked.filter { min($0.affinity, 3) == tier }
            if !items.isEmpty { result.append(Section(title: tierTitle(tier), events: items)) }
        }
        var days: [(String, [FeedEvent])] = []
        for event in events.filter({ $0.affinity <= 0 }).sorted(by: { $0.startDate < $1.startDate }) {
            let label = event.isOpenPoll ? "Date à fixer" : event.startDate.dayLabel(now: now)
            if let index = days.firstIndex(where: { $0.0 == label }) { days[index].1.append(event) } else { days.append((label, [event])) }
        }
        return result + days.map { Section(title: $0.0, events: $0.1) }
    }
}

/// One entry of an intimate friend's calendar, `events-service/events/me/circle`.
struct CircleEntry: Codable, Hashable, Sendable {
    let userId: String
    let start: Date
    let end: Date
    @DefaultFalse var allDay: Bool = false
    let eventId: String?
    let title: String?
    let location: String?
    let description: String?

    init(userId: String, start: Date, end: Date, allDay: Bool = false, eventId: String? = nil, title: String? = nil,
         location: String? = nil, description: String? = nil) {
        self.userId = userId
        self.start = start
        self.end = end
        self.allDay = allDay
        self.eventId = eventId
        self.title = title
        self.location = location
        self.description = description
    }

    /// Overlaps the day; an all-day entry covers its UTC days, as the user's own events do.
    func occurs(on day: Date, calendar: Calendar) -> Bool {
        if allDay {
            let dayStart = AllDay.start(of: day, calendar: calendar)
            return start <= dayStart && max(end, start.addingTimeInterval(1)) > dayStart
        }
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return start < dayEnd && max(end, start.addingTimeInterval(1)) > dayStart
    }
}

/// A friendship made this year, in the profile's year in review.
struct NewFriend: Codable, Hashable, Sendable {
    let userId: String
    let since: Date?
}

/// A friendship that went up a level this year.
struct ClosenessUpgrade: Codable, Hashable, Sendable {
    let userId: String
    let closeness: Closeness
    let at: Date?

    /// « Léa et toi êtes devenus intimes en mars ».
    func label(name: String) -> String {
        let level = closeness == .intimate ? "intimes" : closeness == .close ? "proches" : "amis"
        guard let at else { return "\(name) et toi êtes devenus \(level)" }
        return "\(name) et toi êtes devenus \(level) en \(at.formatted(.dateTime.month(.wide).locale(.wely)))"
    }
}

/// What a newly reached closeness level is celebrated with.
extension Closeness {
    var celebration: (emoji: String, title: String, message: String) {
        switch self {
        case .intimate: ("💝", "maintenant intimes", "Votre lien passe au niveau supérieur.")
        case .close: ("🧡", "maintenant proches", "Vous partagez désormais un peu plus.")
        case .friend: ("🤝", "amis", "")
        }
    }
}

/// « Proposer une sortie »: up to three 2-hour evening slots in the common free time, as wely-web picks them.
enum OutingSlots {
    static let duration: TimeInterval = 2 * 3600
    static let maxSlots = 3
    static let searchDays = 7
    static let searchMinutes = 30
    private static let usefulFrom = 8, usefulTo = 23
    private static let eveningFrom = 18, eveningTo = 21

    /// Free ranges from now on, cut to each day's 8:00–23:00, in order.
    static func withinUsefulHours(_ ranges: [FreeRange], now: Date, calendar: Calendar) -> [FreeRange] {
        var pieces: [FreeRange] = []
        for range in ranges {
            let from = max(range.start, now)
            var day = calendar.startOfDay(for: from)
            while day < range.end {
                if let open = calendar.date(bySettingHour: usefulFrom, minute: 0, second: 0, of: day),
                   let close = calendar.date(bySettingHour: usefulTo, minute: 0, second: 0, of: day) {
                    let start = max(from, open), end = min(range.end, close)
                    if start < end { pieces.append(FreeRange(start: start, end: end)) }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return pieces.sorted { $0.start < $1.start }
    }

    /// The next half hour, or the date itself when it is on one.
    static func roundUpToHalfHour(_ date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.minute, .second, .nanosecond], from: date)
        let extra = Double((parts.minute ?? 0) % 30) * 60 + Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1e9
        return extra == 0 ? date : date.addingTimeInterval(1800 - extra)
    }

    /// One slot per day, starting 18:00–21:00 on the half hour; else the first free stretch; else none.
    static func pick(free ranges: [FreeRange], now: Date = .now, calendar: Calendar = .wely) -> [FreeRange] {
        let pieces = withinUsefulHours(ranges, now: now, calendar: calendar)
        var slots: [FreeRange] = []
        var days = Set<Date>()
        for piece in pieces {
            let day = calendar.startOfDay(for: piece.start)
            guard let evening = calendar.date(bySettingHour: eveningFrom, minute: 0, second: 0, of: day),
                  let latest = calendar.date(bySettingHour: eveningTo, minute: 0, second: 0, of: day) else { continue }
            let start = roundUpToHalfHour(max(piece.start, evening), calendar: calendar)
            let end = start.addingTimeInterval(duration)
            if start <= latest, end <= piece.end, !days.contains(day) {
                slots.append(FreeRange(start: start, end: end))
                days.insert(day)
                if slots.count == maxSlots { break }
            }
        }
        if !slots.isEmpty { return slots }
        guard let first = pieces.first(where: { roundUpToHalfHour($0.start, calendar: calendar) < $0.end }) else { return [] }
        let start = roundUpToHalfHour(first.start, calendar: calendar)
        return [FreeRange(start: start, end: min(start.addingTimeInterval(duration), first.end))]
    }
}
