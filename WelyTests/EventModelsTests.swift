import Foundation
import Testing
@testable import Wely

struct EventModelsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.wely.decode(type, from: Data(json.utf8))
    }

    @Test func decodesAFullEvent() throws {
        let event = try decode(FeedEvent.self, """
        {"id":"e1","title":"Afterwork","organizerId":"u1","startDate":"2026-10-15T17:00:00Z",
         "endDate":"2026-10-15T20:00:00Z","location":"Ninkasi","coordinates":{"latitude":45.7,"longitude":4.8},
         "image":"/demo/a.jpg","description":"Go","visibility":"PUBLIC","communityId":null,
         "poll":{"status":"OPEN","fixedSlotId":null,"slots":[{"id":"s1","start":"2026-10-16T17:00:00Z","end":"2026-10-16T19:00:00Z","yes":["u2"]}]}}
        """)
        #expect(event.title == "Afterwork")
        #expect(event.endDate.timeIntervalSince(event.startDate) == 3 * 3600)
        #expect(event.coordinates == Coordinates(latitude: 45.7, longitude: 4.8))
        #expect(event.visibility == .public)
        #expect(event.isOpenPoll)
        #expect(event.poll?.slots.first?.yes == ["u2"])
        #expect(event.poll?.slots.first?.maybe == [])
    }

    @Test func aMissingEndLastsAnHour() throws {
        let event = try decode(FeedEvent.self, #"{"id":"e1","title":"T","organizerId":"u","startDate":"2026-10-15T17:00:00Z","endDate":null}"#)
        #expect(event.endDate.timeIntervalSince(event.startDate) == FeedEvent.defaultDuration)
        #expect(event.location == "")
        #expect(event.description == "")
        #expect(event.poll == nil)
    }

    @Test func anUnknownVisibilityDoesNotFailTheEvent() throws {
        let event = try decode(FeedEvent.self, #"{"id":"e1","title":"T","organizerId":"u","startDate":"2026-10-15T17:00:00Z","visibility":"SECRET"}"#)
        #expect(event.visibility == .unknown)
    }

    @Test func aPollDropsSlotsWithUnreadableDates() throws {
        let poll = try decode(Poll.self, """
        {"status":"OPEN","slots":[{"id":"ok","start":"2026-10-16T17:00:00Z","end":"2026-10-16T19:00:00Z"},
                                  {"id":"ko","start":"nope","end":"nope"}]}
        """)
        #expect(poll.slots.map(\.id) == ["ok"])
        #expect(poll.fixedSlotId == nil)
    }

    @Test func aLenientListSkipsBrokenEvents() throws {
        let events = try decode([Lenient<FeedEvent>].self, #"[{"id":"e1","title":"T","organizerId":"u"},{"title":"no id"}]"#)
        #expect(events.compactMap(\.value).map(\.id) == ["e1"])
    }

    @Test func profileNamesAndHandle() {
        let user = UserProfile(id: "1", userName: "robin", email: nil, firstName: "Robin", lastName: "Leblanc", hashtag: "4907")
        #expect(user.displayName == "Robin Leblanc")
        #expect(user.handle == "@robin#4907")
        #expect(user.initials == "RL")

        let bare = UserProfile(id: "2", userName: "lea", email: nil, firstName: nil, lastName: "")
        #expect(bare.displayName == "lea")
        #expect(bare.handle == "@lea")
        #expect(bare.initials == "LE")
    }

    @Test func birthdayFieldsDefaultForOlderBackends() throws {
        let event = try decode(FeedEvent.self, #"{"id":"e1","title":"T","organizerId":"u","startDate":"2026-10-15T17:00:00Z"}"#)
        #expect(!event.allDay)
        #expect(event.kind == .standard)
        #expect(event.honoreeId == nil)
        #expect(event.isJoinable)
    }

    @Test func decodesASurpriseAndABirthday() throws {
        let surprise = try decode(FeedEvent.self, #"{"id":"s","title":"S","organizerId":"u","startDate":"2026-10-15T17:00:00Z","kind":"SURPRISE","honoreeId":"lea"}"#)
        #expect(surprise.kind == .surprise)
        #expect(surprise.honoreeId == "lea")
        let birthday = try decode(FeedEvent.self, """
        {"id":"b","title":"Anniversaire de Léa","organizerId":"lea","startDate":"2026-03-12T00:00:00Z","endDate":"2026-03-13T00:00:00Z",
         "allDay":true,"kind":"BIRTHDAY","honoreeId":"lea"}
        """)
        #expect(birthday.allDay)
        #expect(birthday.kind == .birthday)
        #expect(!birthday.isJoinable)
        #expect(try decode(FeedEvent.self, #"{"id":"x","title":"X","organizerId":"u","kind":"WEDDING"}"#).kind == .standard)
    }

    @Test func profileRegistrationFields() throws {
        let fresh = try decode(UserProfile.self, #"{"id":"1","userName":"robin","birthDate":null,"registrationCompleted":false}"#)
        #expect(!fresh.registrationCompleted)
        #expect(fresh.birthDate == nil)
        // A backend that predates the signup completion does not lock anyone out.
        let older = try decode(UserProfile.self, #"{"id":"1","userName":"robin"}"#)
        #expect(older.registrationCompleted)
        let friend = try decode(FriendProfile.self, #"{"id":"2","userName":"lea","birthday":{"month":3,"day":12}}"#)
        #expect(friend.birthday == MonthDay(month: 3, day: 12))
        #expect(try decode(FriendProfile.self, #"{"id":"2","userName":"lea"}"#).birthday == nil)
    }

    @Test func visibilityLabels() {
        #expect(Visibility.friends.label == "Amis")
        #expect(Visibility.community.systemImage == "person.3")
    }

    @Test func coverURLs() {
        let config = AppConfig(gatewayURL: URL(string: "http://gw")!, keycloakURL: URL(string: "http://kc")!, webURL: URL(string: "http://web")!)
        #expect(config.imageURL("/demo/a.jpg")?.absoluteString == "http://web/demo/a.jpg")
        #expect(config.imageURL("https://s3/x.jpg?sig=1")?.absoluteString == "https://s3/x.jpg?sig=1")
        #expect(config.imageURL("") == nil)
        #expect(config.imageURL(nil) == nil)
        #expect(config.tokenEndpoint.absoluteString == "http://kc/realms/wely-realm/protocol/openid-connect/token")
        #expect(config.apiURL.absoluteString == "http://gw/api/v1")
    }

    @Test func aStartMoreThanFiveMinutesBehindIsPast() {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = ISO8601DateFormatter().date(from: "2026-10-19T14:00:00Z")!
        let behind = now.addingTimeInterval(-6 * 60)
        let justBehind = now.addingTimeInterval(-4 * 60)
        #expect(PastDate.isPast(start: behind, end: now, allDay: false, now: now, calendar: paris))
        #expect(!PastDate.isPast(start: justBehind, end: now, allDay: false, now: now, calendar: paris))
    }

    @Test func anAllDayEventIsPastOnlyOnceItsLastDayIsOver() {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = ISO8601DateFormatter().date(from: "2026-10-19T20:00:00Z")!
        let thisMorning = ISO8601DateFormatter().date(from: "2026-10-19T06:00:00Z")!
        let yesterday = ISO8601DateFormatter().date(from: "2026-10-18T10:00:00Z")!
        #expect(!PastDate.isPast(start: thisMorning, end: thisMorning, allDay: true, now: now, calendar: paris))
        #expect(!PastDate.isPast(start: yesterday, end: thisMorning, allDay: true, now: now, calendar: paris))
        #expect(PastDate.isPast(start: yesterday, end: yesterday, allDay: true, now: now, calendar: paris))
    }

    @Test func aPollWithASlotAlreadyStartedIsPast() {
        let now = ISO8601DateFormatter().date(from: "2026-10-19T14:00:00Z")!
        let later = EventCreateRequest.Slot(start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200))
        let started = EventCreateRequest.Slot(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(3600))
        #expect(!PastDate.hasPastSlot([later], now: now))
        #expect(PastDate.hasPastSlot([later, started], now: now))
    }

    @Test func thePastDateRefusalIsWorded() {
        #expect(ErrorMessages.text(for: "EVT-BUS-038") == PastDate.message)
    }
}
