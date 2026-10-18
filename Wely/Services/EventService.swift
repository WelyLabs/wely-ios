import Foundation

/// `events-service/events`, as wely-web's EventService, ScheduleService and ExpenseService call it.
struct EventService {
    let api: APIClient
    private let base = "events-service/events"

    // MARK: Lists

    func subscribed() async throws -> [FeedEvent] { try await list("\(base)/me/subscribed") }
    /// By affinity, events with the closest friends come first; otherwise by date.
    func feed(byAffinity: Bool = false) async throws -> [FeedEvent] {
        try await list("\(base)/me/feed", query: ["rank": byAffinity ? "affinity" : nil])
    }
    func myPolls() async throws -> [FeedEvent] { try await list("\(base)/me/polls") }
    /// The user's and their friends' birthdays between two instants (400 days at most).
    func birthdays(from: Date, to: Date) async throws -> [BirthdayOccurrence] {
        let lenient: [Lenient<BirthdayOccurrence>] = try await api.get("\(base)/me/birthdays", query: [
            "from": from.ISO8601Format(), "to": to.ISO8601Format(),
        ])
        return lenient.compactMap(\.value)
    }
    func community(_ communityId: String) async throws -> [FeedEvent] { try await list("\(base)/community/\(communityId)") }

    func map(south: Double, west: Double, north: Double, east: Double) async throws -> [FeedEvent] {
        let lenient: [Lenient<FeedEvent>] = try await api.get("\(base)/map", query: [
            "south": "\(south)", "west": "\(west)", "north": "\(north)", "east": "\(east)",
        ])
        return lenient.compactMap(\.value)
    }

    // MARK: One event

    func event(_ id: String) async throws -> FeedEvent { try await api.get("\(base)/\(id)") }
    func participants(_ id: String) async throws -> EventParticipants { try await api.get("\(base)/\(id)/participants") }

    func create(_ request: EventCreateRequest) async throws -> FeedEvent { try await api.post(base, body: request) }
    func update(_ id: String, _ request: EventUpdateRequest) async throws -> FeedEvent { try await api.put("\(base)/\(id)", body: request) }
    func delete(_ id: String) async throws { try await api.delete("\(base)/\(id)") }

    /// Joins, or leaves when already in (non-organizer).
    func toggleSubscription(_ id: String) async throws -> FeedEvent { try await api.post("\(base)/\(id)/subscribe") }
    func leave(_ id: String, choice: LeaveChoice) async throws -> LeaveResult { try await api.post("\(base)/\(id)/leave", body: choice) }
    func respond(_ id: String, answer: PollAnswer) async throws -> FeedEvent {
        try await api.put("\(base)/\(id)/response", body: AnswerRequest(answer: answer))
    }

    func uploadCover(_ id: String, jpeg: Data) async throws -> FeedEvent {
        try await api.upload("\(base)/\(id)/cover", file: UploadFile(fileName: "cover.jpg", data: jpeg))
    }
    func removeCover(_ id: String) async throws { try await api.delete("\(base)/\(id)/cover") }

    // MARK: Poll

    func vote(_ id: String, answers: [String: PollAnswer]) async throws -> Poll {
        try await api.put("\(base)/\(id)/poll/ballot", body: BallotRequest(answers: answers))
    }
    func fixDate(_ id: String, slotId: String) async throws -> FeedEvent {
        try await api.post("\(base)/\(id)/poll/fix", body: SlotChoice(slotId: slotId))
    }

    // MARK: Schedule

    func conflicts(start: Date, end: Date, excluding eventId: String? = nil) async throws -> [FeedEvent] {
        let lenient: [Lenient<FeedEvent>] = try await api.post("\(base)/me/conflicts", body: ConflictsRequest(start: start, end: end, excludedEventId: eventId))
        return lenient.compactMap(\.value)
    }
    func conflicts(of eventId: String) async throws -> [FeedEvent] {
        let lenient: [Lenient<FeedEvent>] = try await api.get("\(base)/\(eventId)/conflicts")
        return lenient.compactMap(\.value)
    }
    func pollStreamURL(_ eventId: String) -> URL { api.url("\(base)/\(eventId)/poll/stream") }
    func reschedule(_ id: String, start: Date, end: Date) async throws -> FeedEvent {
        try await api.put("\(base)/\(id)/schedule", body: FreeRange(start: start, end: end))
    }
    func freeSlots(_ search: FreeSlotSearch) async throws -> [FreeRange] { try await api.post("\(base)/me/free-slots", body: search) }

    // MARK: People

    func friendCalendar(_ friendId: String, from: Date, to: Date) async throws -> [FriendCalendarEntry] {
        try await api.get("\(base)/users/\(friendId)/calendar", query: ["from": from.ISO8601Format(), "to": to.ISO8601Format()])
    }
    func mySummary() async throws -> ProfileSummary { try await api.get("\(base)/me/summary") }

    // MARK: Friendships

    /// Up to three close friends not seen for a while.
    func reunions() async throws -> [ReunionCandidate] {
        let lenient: [Lenient<ReunionCandidate>] = try await api.get("\(base)/me/reunions")
        return lenient.compactMap(\.value)
    }
    /// « Plus tard »: that friend is not suggested again for 30 days.
    func dismissReunion(_ friendId: String) async throws { try await api.send("POST", "\(base)/me/reunions/\(friendId)/dismiss") }
    func memories(with friendId: String) async throws -> FriendshipMemories { try await api.get("\(base)/me/friendships/\(friendId)/memories") }
    /// The intimate friends' calendars between two instants (62 days at most).
    func circle(from: Date, to: Date) async throws -> [CircleEntry] {
        let lenient: [Lenient<CircleEntry>] = try await api.get("\(base)/me/circle", query: ["from": from.ISO8601Format(), "to": to.ISO8601Format()])
        return lenient.compactMap(\.value)
    }
    func friendOverview(_ friendId: String) async throws -> FriendOverview { try await api.get("\(base)/users/\(friendId)/overview") }

    // MARK: Expenses

    func expenses(_ eventId: String) async throws -> [Expense] { try await api.get("\(base)/\(eventId)/expenses") }
    func ledger(_ eventId: String) async throws -> Ledger { try await api.get("\(base)/\(eventId)/expenses/ledger") }
    func addExpense(_ eventId: String, _ request: ExpenseRequest) async throws -> Expense {
        try await api.post("\(base)/\(eventId)/expenses", body: request)
    }
    func updateExpense(_ eventId: String, _ expenseId: String, _ request: ExpenseRequest) async throws -> Expense {
        try await api.put("\(base)/\(eventId)/expenses/\(expenseId)", body: request)
    }
    func deleteExpense(_ eventId: String, _ expenseId: String) async throws {
        try await api.delete("\(base)/\(eventId)/expenses/\(expenseId)")
    }
    func settle(_ eventId: String, _ request: SettlementRequest) async throws -> Expense {
        try await api.post("\(base)/\(eventId)/expenses/settlements", body: request)
    }

    /// One unreadable event is left out rather than emptying the list.
    private func list(_ path: String, query: [String: String?] = [:]) async throws -> [FeedEvent] {
        let lenient: [Lenient<FeedEvent>] = try await api.get(path, query: query)
        return lenient.compactMap(\.value)
    }
}
