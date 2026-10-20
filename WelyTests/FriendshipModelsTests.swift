import Foundation
import Testing
@testable import Wely

private let config = AppConfig(gatewayURL: URL(string: "http://gw")!, keycloakURL: URL(string: "http://kc")!, webURL: URL(string: "http://web")!)

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.wely.decode(type, from: Data(json.utf8))
}

private var paris: Calendar {
    var calendar = Calendar.wely
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    // Monday 19 October 2026, then the following days.
    paris.date(from: DateComponents(year: 2026, month: 10, day: 19 + day, hour: hour, minute: minute))!
}

struct ReunionAndMemoriesTests {
    @Test func decodesAReunionCandidate() throws {
        let candidate = try decode(ReunionCandidate.self, """
        {"friendId":"hugo","name":"Hugo","closeness":"CLOSE","lastSharedAt":"2026-06-14T09:00:00Z","lastSharedEventId":"e1",
         "lastSharedTitle":"Week-end à Annecy","monthsApart":4}
        """)
        #expect(candidate.id == "hugo")
        #expect(candidate.closeness == .close)
        #expect(candidate.lastSharedEventId == "e1")
        #expect(candidate.subtitle == "Pas vus depuis 4 mois · Week-end à Annecy")
    }

    @Test func aReunionWithoutHistoryOrNameStillReads() throws {
        let never = try decode(ReunionCandidate.self, #"{"friendId":"ines","closeness":"SOULMATE","lastSharedAt":null,"monthsApart":null}"#)
        #expect(never.name == "Un ami")
        #expect(never.closeness == nil)
        #expect(never.subtitle == "Aucune sortie partagée sur Wely")
    }

    @Test func aRecentReunionSaysAWhile() {
        let recent = ReunionCandidate(friendId: "a", name: "A", lastSharedAt: .now, monthsApart: 1)
        #expect(recent.subtitle == "Pas vus depuis un moment")
        let untitled = ReunionCandidate(friendId: "a", name: "A", lastSharedAt: .now, monthsApart: 6)
        #expect(untitled.subtitle == "Pas vus depuis 6 mois")
    }

    @Test func decodesMemoriesAndDropsAnUnreadableHighlight() throws {
        let memories = try decode(FriendshipMemories.self, """
        {"friendId":"lea","name":"Léa","closeness":"INTIMATE","since":"2025-03-03T00:00:00Z","years":1,"days":412,"sharedCount":14,
         "first":{"eventId":"e1","title":"Bloc","startDate":"2025-03-10T18:00:00Z","imageUrl":null},"last":null,
         "highlights":[{"eventId":"e2","title":"Annecy","startDate":"2026-09-01T09:00:00Z","imageUrl":"https://s3/x.jpg"},{"title":"no id"}]}
        """)
        #expect(memories.closeness == .intimate)
        #expect(memories.first?.eventId == "e1")
        #expect(memories.last == nil)
        #expect(memories.highlights.map(\.eventId) == ["e2"])
        #expect(memories.highlights.first?.imageUrl == "https://s3/x.jpg")
        #expect(memories.title == "1 an d'amitié avec Léa")
        #expect(memories.sharedLabel == "14 sorties ensemble")
    }

    @Test func memoriesTitlesCountYearsThenDays() {
        #expect(FriendshipMemories(friendId: "a", name: "Hugo", years: 3, days: 1100).title == "3 ans d'amitié avec Hugo")
        #expect(FriendshipMemories(friendId: "a", name: "Hugo", years: 0, days: 40).title == "40 jours d'amitié avec Hugo")
        #expect(FriendshipMemories(friendId: "a", name: "Hugo", years: 0, days: 1).title == "1 jour d'amitié avec Hugo")
        #expect(FriendshipMemories(friendId: "a", name: "Hugo", sharedCount: 1).sharedLabel == "1 sortie ensemble")
    }

    @Test func sinceReadsInFrench() {
        let since = paris.date(from: DateComponents(year: 2025, month: 3, day: 3, hour: 12))!
        #expect(FriendshipMemories(friendId: "a", name: "L", since: since).sinceLabel == "depuis le 3 mars 2025")
        #expect(FriendshipMemories(friendId: "a", name: "L").sinceLabel == nil)
    }

    @Test func theAnniversaryIsTheDayOfSinceAfterAYear() {
        let since = paris.date(from: DateComponents(year: 2025, month: 10, day: 18, hour: 9))!
        let today = paris.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 20))!
        let tomorrow = paris.date(byAdding: .day, value: 1, to: today)!
        #expect(FriendshipMemories(friendId: "a", name: "L", since: since, years: 1).isAnniversary(today: today, calendar: paris))
        #expect(!FriendshipMemories(friendId: "a", name: "L", since: since, years: 1).isAnniversary(today: tomorrow, calendar: paris))
        #expect(!FriendshipMemories(friendId: "a", name: "L", since: since, years: 0).isAnniversary(today: today, calendar: paris))
        #expect(!FriendshipMemories(friendId: "a", name: "L", years: 2).isAnniversary(today: today, calendar: paris))
    }
}

struct FriendsGoingTests {
    @Test func decodesWhoGoesAndTheAffinity() throws {
        let event = try decode(FeedEvent.self, """
        {"id":"e1","title":"Rando","organizerId":"o","startDate":"2026-10-20T08:00:00Z",
         "friendsGoing":[{"userId":"lea","closeness":"INTIMATE"},{"userId":"x","closeness":"BESTIE"},{"closeness":"CLOSE"}],
         "friendsGoingCount":7,"affinity":3}
        """)
        #expect(event.friendsGoing == [FriendGoing(userId: "lea", closeness: .intimate), FriendGoing(userId: "x", closeness: nil)])
        #expect(event.friendsGoingCount == 7)
        #expect(event.affinity == 3)
        #expect(event.friendsGoingLabel == "1 de tes proches y va")
    }

    @Test func anOlderBackendSendsNobody() throws {
        let event = try decode(FeedEvent.self, #"{"id":"e1","title":"Rando","organizerId":"o","startDate":"2026-10-20T08:00:00Z"}"#)
        #expect(event.friendsGoing.isEmpty)
        #expect(event.friendsGoingCount == 0)
        #expect(event.affinity == 0)
        #expect(event.friendsGoingLabel == nil)
        #expect(event.with(start: .now).affinity == 0)
    }

    @Test func labelsCountCloseFriendsThenEveryFriend() {
        let intimate = FriendGoing(userId: "a", closeness: .intimate)
        let close = FriendGoing(userId: "b", closeness: .close)
        let friend = FriendGoing(userId: "c", closeness: .friend)
        #expect(FriendsGoing.label([intimate, close, friend], total: 7) == "2 de tes proches y vont")
        #expect(FriendsGoing.label([close], total: 1) == "1 de tes proches y va")
        #expect(FriendsGoing.label([friend, friend], total: 7) == "7 amis y vont")
        #expect(FriendsGoing.label([], total: 1) == "1 ami y va")
        #expect(FriendsGoing.label([friend, friend], total: 0) == "2 amis y vont")
        #expect(FriendsGoing.label([], total: 0) == nil)
    }

    @Test func facesAreTheCloseOnesWhenThereAre() {
        let friend = FriendGoing(userId: "c", closeness: .friend)
        let close = FriendGoing(userId: "b", closeness: .close)
        let intimate = FriendGoing(userId: "a", closeness: .intimate)
        #expect(FriendsGoing.faces([friend, close, intimate]) == ["a", "b"])
        #expect(FriendsGoing.faces([friend]) == ["c"])
    }

    @Test func aBirthdayShowsNoFriendsGoing() {
        let birthday = FeedEvent(id: "b", title: "Anniversaire", organizerId: "o", startDate: .now, kind: .birthday,
                                 friendsGoing: [FriendGoing(userId: "a", closeness: .intimate)], friendsGoingCount: 1, affinity: 3)
        #expect(birthday.friendsGoingLabel == nil)
    }

    @Test func theRankedFeedListsTiersThenDays() {
        let now = at(0, 9)
        let event = { (id: String, day: Int, affinity: Int) in
            FeedEvent(id: id, title: id, organizerId: "o", startDate: at(day, 19), affinity: affinity)
        }
        // As the server ranks them: affinity first, then date.
        let later = FeedEvent(id: "n1b", title: "n1b", organizerId: "o", startDate: at(1, 21))
        let sections = FeedRanking.sections([event("i9", 9, 3), event("c1", 1, 2), event("c5", 5, 2), event("f2", 2, 1),
                                             event("n2", 2, 0), later, event("n1", 1, 0)], now: now)
        #expect(sections.map(\.title).prefix(3) == ["💝 Avec tes intimes", "🧡 Avec tes proches", "Avec tes amis"])
        #expect(sections[1].events.map(\.id) == ["c1", "c5"])
        #expect(sections.count == 5)
        #expect(sections[3].events.map(\.id) == ["n1", "n1b"])
        #expect(sections[4].events.map(\.id) == ["n2"])
    }

    @Test func anUnrankedFeedIsGroupedByDayAsBefore() {
        let now = at(0, 9)
        let poll = FeedEvent(id: "p", title: "p", organizerId: "o", startDate: at(3, 19),
                             poll: Poll(status: .open, slots: [PollSlot(id: "s", start: at(3, 19), end: at(3, 21))]))
        let sections = FeedRanking.sections([FeedEvent(id: "b", title: "b", organizerId: "o", startDate: at(2, 19)), poll,
                                             FeedEvent(id: "a", title: "a", organizerId: "o", startDate: at(1, 19))], now: now)
        #expect(sections.map { $0.events.map(\.id) } == [["a"], ["b"], ["p"]])
        #expect(sections.last?.title == "Date à fixer")
    }
}

struct CircleAndYearTests {
    @Test func decodesACircleEntryAndPlacesItOnItsDays() throws {
        let entry = try decode(CircleEntry.self, #"{"userId":"lea","start":"2026-10-20T18:00:00Z","end":"2026-10-20T21:00:00Z","eventId":null,"title":null}"#)
        #expect(entry.userId == "lea")
        #expect(!entry.allDay)
        #expect(entry.title == nil)
        #expect(entry.occurs(on: at(1, 0), calendar: paris))
        #expect(!entry.occurs(on: at(2, 0), calendar: paris))

        let allDay = CircleEntry(userId: "lea", start: try Date("2026-10-21T00:00:00Z", strategy: .iso8601),
                                 end: try Date("2026-10-23T00:00:00Z", strategy: .iso8601), allDay: true)
        #expect(allDay.occurs(on: at(2, 12), calendar: paris))
        #expect(allDay.occurs(on: at(3, 12), calendar: paris))
        #expect(!allDay.occurs(on: at(4, 12), calendar: paris))
    }

    @Test func theSummaryReadsTheYearsFriendships() throws {
        let summary = try decode(ProfileSummary.self, """
        {"outingsThisYear":3,"outingsThisMonth":1,"organizedThisYear":0,"placesThisYear":2,
         "newFriendsThisYear":[{"userId":"n","since":"2026-02-01T10:00:00Z"}],
         "upgradesThisYear":[{"userId":"lea","closeness":"INTIMATE","at":"2026-03-12T10:00:00Z"}],
         "topFriendsThisYear":[{"userId":"lea","outingsTogether":9}]}
        """)
        #expect(summary.newFriendsThisYear.map(\.userId) == ["n"])
        #expect(summary.upgradesThisYear.first?.closeness == .intimate)
        #expect(summary.topFriendsThisYear == [Companion(userId: "lea", outingsTogether: 9)])
        #expect(summary.hasFriendshipYear)
    }

    @Test func anOlderSummaryHasNoFriendshipYear() throws {
        let summary = try decode(ProfileSummary.self, #"{"outingsThisYear":3,"outingsThisMonth":1,"organizedThisYear":0,"placesThisYear":2}"#)
        #expect(summary.newFriendsThisYear.isEmpty)
        #expect(!summary.hasFriendshipYear)
    }

    @Test func upgradesReadAsASentence() {
        let march = paris.date(from: DateComponents(year: 2026, month: 3, day: 12))!
        #expect(ClosenessUpgrade(userId: "lea", closeness: .intimate, at: march).label(name: "Léa") == "Léa et toi êtes devenus intimes en mars")
        #expect(ClosenessUpgrade(userId: "hugo", closeness: .close, at: nil).label(name: "Hugo") == "Hugo et toi êtes devenus proches")
    }

    @Test func eachLevelHasItsCelebration() {
        #expect(Closeness.intimate.celebration.emoji == "💝")
        #expect(Closeness.intimate.celebration.title == "maintenant intimes")
        #expect(Closeness.close.celebration.emoji == "🧡")
        #expect(Closeness.close.celebration.message == "Vous partagez désormais un peu plus.")
    }
}

struct OutingSlotsTests {
    @Test func picksOneEveningPerDayAndThreeAtMost() {
        let free = [
            FreeRange(start: at(0, 17), end: at(0, 23, 30)),
            FreeRange(start: at(0, 23, 45), end: at(1, 1)),
            FreeRange(start: at(1, 19, 15), end: at(1, 22)),
            FreeRange(start: at(2, 8), end: at(3, 23, 59)),
        ]
        let slots = OutingSlots.pick(free: free, now: at(0, 10), calendar: paris)
        #expect(slots == [
            FreeRange(start: at(0, 18), end: at(0, 20)),
            FreeRange(start: at(1, 19, 30), end: at(1, 21, 30)),
            FreeRange(start: at(2, 18), end: at(2, 20)),
        ])
    }

    @Test func withoutAnEveningItTakesTheFirstFreeStretch() {
        let morning = OutingSlots.pick(free: [FreeRange(start: at(0, 10), end: at(0, 11, 10))], now: at(0, 9), calendar: paris)
        #expect(morning == [FreeRange(start: at(0, 10), end: at(0, 11, 10))])
        let late = OutingSlots.pick(free: [FreeRange(start: at(0, 21, 10), end: at(0, 23))], now: at(0, 9), calendar: paris)
        #expect(late == [FreeRange(start: at(0, 21, 30), end: at(0, 23))])
    }

    @Test func pastOrTooShortTimeGivesNothing() {
        #expect(OutingSlots.pick(free: [], now: at(0, 9), calendar: paris).isEmpty)
        #expect(OutingSlots.pick(free: [FreeRange(start: at(0, 8), end: at(0, 19))], now: at(0, 18, 40), calendar: paris).isEmpty)
        #expect(OutingSlots.pick(free: [FreeRange(start: at(-1, 8), end: at(-1, 23))], now: at(0, 9), calendar: paris).isEmpty)
    }

    @Test func roundsUpToTheHalfHour() {
        #expect(OutingSlots.roundUpToHalfHour(at(0, 18), calendar: paris) == at(0, 18))
        #expect(OutingSlots.roundUpToHalfHour(at(0, 18, 1), calendar: paris) == at(0, 18, 30))
        #expect(OutingSlots.roundUpToHalfHour(at(0, 18, 31), calendar: paris) == at(0, 19))
    }

    @Test func severalSlotsOpenAPoll() {
        let draft = EventFormView.Draft.outing(slots: [FreeRange(start: at(0, 18), end: at(0, 20)), FreeRange(start: at(1, 18), end: at(1, 20))])
        #expect(draft.title == "Sortie")
        #expect(draft.slots.count == 2)
        #expect(draft.start == at(0, 18))
        #expect(draft.kind == .standard)
    }

    @Test func oneSlotIsAFixedDateAndNoneTheNextEvening() {
        let one = EventFormView.Draft.outing(slots: [FreeRange(start: at(0, 18), end: at(0, 20))])
        #expect(one.slots.isEmpty)
        #expect(one.start == at(0, 18))
        #expect(one.end == at(0, 20))

        let none = EventFormView.Draft.outing(slots: [], now: at(0, 20), calendar: paris)
        #expect(none.start == at(1, 19))
        #expect(none.end == at(1, 21))
        #expect(EventFormView.Draft.outing(slots: [], now: at(0, 10), calendar: paris).start == at(0, 19))
    }
}

struct FriendshipLinksTests {
    @Test func friendLinksOpenTheProposalOrTheMemories() {
        #expect(AppDestination(webPath: "/friends/hugo?propose=1") == .proposeOuting(friendId: "hugo"))
        #expect(AppDestination(webPath: "/friends/hugo?propose=0") == .person("hugo"))
        #expect(AppDestination(webPath: "/friends/lea/memories") == .memories(friendId: "lea"))
        #expect(AppDestination(webPath: "/friends/lea/other") == nil)
        #expect(Route(.proposeOuting(friendId: "hugo")) == .proposeOuting("hugo"))
        #expect(Route(.memories(friendId: "lea")) == .memories("lea"))
    }

    @Test func friendshipNotificationsHaveTheirIcons() {
        let icon = { (type: String) in
            AppNotification(id: "n", type: type, category: "FRIENDS", title: "", body: "", link: nil, groupKey: nil, count: nil, actorId: nil,
                            createdAt: .now).systemImage
        }
        #expect(icon("REUNION_NUDGE") == "hand.wave.fill")
        #expect(icon("FRIENDSHIP_ANNIVERSARY") == "heart.text.square.fill")
        #expect(icon("CLOSENESS_UPGRADED") == "heart.circle.fill")
    }
}

@MainActor
struct FriendshipServiceTests {
    private func signedIn(_ responses: [(Int, String)]) -> (AppModel, StubTransport) {
        let http = StubTransport(responses)
        let stored = TokenSet(accessToken: "AT", refreshToken: "RT", idToken: nil, expiresAt: .distantFuture)
        let session = AuthSession(config: config, store: InMemoryTokenStore(stored), http: http)
        return (AppModel(session: session, http: http), http)
    }

    @Test func theExploreFeedAsksForTheAffinityRanking() async throws {
        let (app, http) = signedIn([(200, "[]"), (200, "[]")])
        _ = try await app.events.feed(byAffinity: true)
        _ = try await app.events.feed()
        #expect(http.requests[0].url?.path() == "/api/v1/events-service/events/me/feed")
        #expect(http.requests[0].url?.query() == "rank=affinity")
        #expect(http.requests[1].url?.query() == nil)
    }

    @Test func reunionsAreReadLeniently() async throws {
        let (app, http) = signedIn([(200, #"[{"friendId":"hugo","name":"Hugo","closeness":"CLOSE","monthsApart":4},{"name":"broken"}]"#)])
        let reunions = try await app.events.reunions()
        #expect(reunions.map(\.friendId) == ["hugo"])
        #expect(http.requests[0].url?.path() == "/api/v1/events-service/events/me/reunions")
    }

    @Test func dismissingAReunionPostsForThatFriend() async throws {
        let (app, http) = signedIn([(204, "")])
        try await app.events.dismissReunion("hugo")
        #expect(http.requests[0].httpMethod == "POST")
        #expect(http.requests[0].url?.path() == "/api/v1/events-service/events/me/reunions/hugo/dismiss")
    }

    @Test func dismissingAStrangerFails() async {
        let (app, _) = signedIn([(404, #"{"code":"EVT-BUS-036"}"#)])
        await #expect(throws: APIError.self) { try await app.events.dismissReunion("nobody") }
    }

    @Test func memoriesAreAskedForAFriend() async throws {
        let (app, http) = signedIn([(200, #"{"friendId":"lea","name":"Léa","years":1,"days":400,"sharedCount":3,"highlights":[]}"#)])
        let memories = try await app.events.memories(with: "lea")
        #expect(memories.sharedCount == 3)
        #expect(http.requests[0].url?.path() == "/api/v1/events-service/events/me/friendships/lea/memories")
    }

    @Test func memoriesOfAStrangerAre404() async {
        let (app, _) = signedIn([(404, "")])
        do {
            _ = try await app.events.memories(with: "x")
            Issue.record("a 404 was expected")
        } catch let error as APIError {
            #expect(error.status == 404)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func theCircleIsAskedForARange() async throws {
        let (app, http) = signedIn([(200, #"[{"userId":"lea","start":"2026-10-20T18:00:00Z","end":"2026-10-20T20:00:00Z","title":"Bloc"},{"userId":"x"}]"#)])
        let from = try Date("2026-09-28T00:00:00Z", strategy: .iso8601)
        let to = try Date("2026-11-09T00:00:00Z", strategy: .iso8601)
        let entries = try await app.events.circle(from: from, to: to)
        #expect(entries.map(\.title) == ["Bloc"])
        let url = try #require(http.requests[0].url)
        #expect(url.path() == "/api/v1/events-service/events/me/circle")
        #expect(url.query() == "from=2026-09-28T00:00:00Z&to=2026-11-09T00:00:00Z")
    }

    @Test func theProposalSearchesTheWeekWithThatFriend() async throws {
        let (app, http) = signedIn([(200, #"[{"start":"2026-10-19T16:00:00Z","end":"2026-10-19T21:00:00Z"}]"#)])
        let now = at(0, 10)
        let draft = await OutingProposal.draft(with: "hugo", events: app.events, now: now, calendar: paris)
        #expect(draft.start == at(0, 18))
        #expect(draft.slots.isEmpty)
        let body = try #require(http.requests[0].httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["friendIds"] as? [String] == ["hugo"])
        #expect(body["durationMinutes"] as? Int == 30)
        #expect(http.requests[0].url?.path() == "/api/v1/events-service/events/me/free-slots")
    }

    @Test func aFailedSearchStillOpensTheForm() async {
        let (app, _) = signedIn([(502, "")])
        let draft = await OutingProposal.draft(with: "hugo", events: app.events, now: at(0, 10), calendar: paris)
        #expect(draft.start == at(0, 19))
    }

    @Test func friendshipLinksGoToTheSocialTab() {
        let (app, _) = signedIn([])
        app.selectedTab = .calendar
        app.open(.memories(friendId: "lea"))
        #expect(app.selectedTab == .social)
        #expect(app.pendingDestination == .memories(friendId: "lea"))
        app.selectedTab = .feed
        app.open(.proposeOuting(friendId: "hugo"))
        #expect(app.selectedTab == .social)
    }
}

/// The demo backend, as `-WelyDemo` shows the features.
struct FriendshipDemoTests {
    private func events() -> EventService {
        let session = AuthSession(store: InMemoryTokenStore(TokenSet(accessToken: "t", refreshToken: nil, idToken: nil, expiresAt: .distantFuture)))
        return EventService(api: APIClient(session: session, http: DemoTransport()))
    }

    @Test func theDemoFeedIsRankedWithFriendsGoing() async throws {
        let feed = try await events().feed(byAffinity: true)
        #expect(feed.map(\.affinity) == feed.map(\.affinity).sorted(by: >))
        #expect(feed.first?.affinity == 3)
        #expect(feed.contains { $0.friendsGoingLabel?.contains("de tes proches") == true })
        #expect(feed.allSatisfy { !$0.friendsGoing.contains { $0.userId == DemoStore.me } })
    }

    @Test func theDemoHasReunionsMemoriesAndACircle() async throws {
        let service = events()
        let reunions = try await service.reunions()
        #expect(reunions.map(\.friendId) == ["hugo", "ines"])
        try await service.dismissReunion("hugo")
        #expect(try await service.reunions().map(\.friendId) == ["ines"])

        let memories = try await service.memories(with: "lea")
        #expect(memories.years == 1)
        #expect(memories.isAnniversary())
        #expect(!memories.highlights.isEmpty)
        await #expect(throws: APIError.self) { try await service.memories(with: "camille") }

        let circle = try await service.circle(from: .now.addingTimeInterval(-86_400 * 30), to: .now.addingTimeInterval(86_400 * 30))
        #expect(!circle.isEmpty)
        #expect(Set(circle.map(\.userId)) == ["lea"])
    }
}
