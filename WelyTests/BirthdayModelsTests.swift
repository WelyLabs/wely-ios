import Foundation
import Testing
@testable import Wely

private let config = AppConfig(gatewayURL: URL(string: "http://gw")!, keycloakURL: URL(string: "http://kc")!, webURL: URL(string: "http://web")!)

struct BirthdayModelsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.wely.decode(type, from: Data(json.utf8))
    }

    @Test func decodesAFriendsBirthdayWithItsSurprise() throws {
        let occurrence = try decode(BirthdayOccurrence.self, """
        {"userId":"u1","name":"Léa","date":"2027-03-12","mine":false,"closeness":"CLOSE","canOrganize":false,
         "surprise":{"eventId":"e1","organizerId":"u2","joined":true}}
        """)
        #expect(occurrence.id == "u1#2027-03-12")
        #expect(occurrence.closeness == .close)
        #expect(occurrence.surprise == .init(eventId: "e1", organizerId: "u2", joined: true))
        #expect(occurrence.style == .close)
        #expect(occurrence.day(in: .wely) == Calendar.wely.date(from: DateComponents(year: 2027, month: 3, day: 12)))
    }

    @Test func decodesMyOwnBirthdayWithoutCloseness() throws {
        let occurrence = try decode(BirthdayOccurrence.self, #"{"userId":"me","name":"Robin","date":"2026-10-18","mine":true,"closeness":null,"surprise":null}"#)
        #expect(occurrence.mine)
        #expect(!occurrence.canOrganize)
        #expect(occurrence.surprise == nil)
        #expect(occurrence.style == .mine)
    }

    @Test func styleFollowsCloseness() {
        let base = { (closeness: Closeness?) in BirthdayOccurrence(userId: "u", name: "N", date: "2026-10-20", closeness: closeness) }
        #expect(base(.friend).style == .friend)
        #expect(base(.close).style == .close)
        #expect(base(.intimate).style == .intimate)
        #expect(base(nil).style == .friend)
        #expect([BirthdayStyle.friend, .close, .intimate, .mine].map(\.emoji) == ["🎈", "🎁", "💝", "🎂"])
    }

    @Test func theLoudestStyleWinsTheDay() {
        let friend = BirthdayOccurrence(userId: "a", name: "A", date: "2026-10-20", closeness: .friend)
        let intimate = BirthdayOccurrence(userId: "b", name: "B", date: "2026-10-20", closeness: .intimate)
        let mine = BirthdayOccurrence(userId: "me", name: "Moi", date: "2026-10-20", mine: true)
        #expect(BirthdayStyle.strongest(of: []) == nil)
        #expect(BirthdayStyle.strongest(of: [friend, intimate]) == .intimate)
        #expect(BirthdayStyle.strongest(of: [intimate, mine, friend]) == .mine)
    }

    @Test func monthDaysReadInFrench() throws {
        let birthday = try decode(MonthDay.self, #"{"month":3,"day":12}"#)
        #expect(birthday.label == "12 mars")
    }

    @Test func daysAreWrittenWithoutTimeZone() {
        let calendar = Calendar.wely
        let day = calendar.date(from: DateComponents(year: 1995, month: 3, day: 2, hour: 23, minute: 30))!
        #expect(DayString.string(from: day, calendar: calendar) == "1995-03-02")
        #expect(DayString.date(from: "1995-03-02", calendar: calendar) == calendar.date(from: DateComponents(year: 1995, month: 3, day: 2)))
        #expect(DayString.date(from: "nope", calendar: calendar) == nil)
    }

    @Test func allDayRangesRunFromUTCMidnightToTheNextDay() {
        var paris = Calendar.wely
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let first = paris.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 0, minute: 30))!
        let range = AllDay.range(from: first, through: first, calendar: paris)
        #expect(range.start.ISO8601Format() == "2026-03-12T00:00:00Z")
        #expect(range.end.ISO8601Format() == "2026-03-13T00:00:00Z")

        let last = paris.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 18))!
        #expect(AllDay.range(from: first, through: last, calendar: paris).end.ISO8601Format() == "2026-03-15T00:00:00Z")
        #expect(DayString.string(from: AllDay.localDay(of: range.start, calendar: paris), calendar: paris) == "2026-03-12")
    }

    @Test func allDayLabels() {
        let start = try! Date("2026-03-12T00:00:00Z", strategy: .iso8601)
        #expect(AllDay.label(start, start.addingTimeInterval(86_400)) == "Jeudi 12 mars · Toute la journée")
        #expect(AllDay.label(start, start.addingTimeInterval(3 * 86_400)) == "Du 12 mars au 14 mars")
    }

    @Test func signupStepsAreOwedUntilTheBackendSaysDone() {
        #expect(SignupStep.pending(for: nil).isEmpty)
        #expect(SignupStep.pending(for: UserProfile(id: "1", userName: "r", registrationCompleted: true)).isEmpty)
        #expect(SignupStep.pending(for: UserProfile(id: "1", userName: "r", registrationCompleted: false)) == [.birthDate])
    }

    @Test func signupAnswersBecomeTheRegistrationRequest() throws {
        let calendar = Calendar.wely
        let answers = SignupAnswers(birthDate: calendar.date(from: DateComponents(year: 1995, month: 3, day: 12))!)
        let json = try JSONEncoder.wely.encode(answers.request(calendar: calendar))
        #expect(String(data: json, encoding: .utf8) == #"{"birthDate":"1995-03-12"}"#)

        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18))!
        let range = SignupAnswers.birthDateRange(now: now, calendar: calendar)
        #expect(calendar.component(.year, from: range.lowerBound) == 1906)
        #expect(calendar.component(.year, from: range.upperBound) == 2013)
    }

    @Test func aSurpriseDraftIsPrefilled() {
        let calendar = Calendar.wely
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let draft = EventFormView.Draft.surprise(for: "lea", name: "Léa", on: day, calendar: calendar)
        #expect(draft.kind == .surprise)
        #expect(draft.honoreeId == "lea")
        #expect(draft.title == "Anniversaire surprise de Léa 🎉")
        #expect(draft.details == "🤫 Léa ne voit pas cet événement. Invite ses amis et choisis le lieu.")
        #expect(draft.visibility == .friends)
        #expect(calendar.component(.hour, from: draft.start) == 19)
        #expect(calendar.component(.hour, from: draft.end) == 23)
        #expect(calendar.isDate(draft.start, inSameDayAs: day))
    }
}

@MainActor
struct BirthdayServiceTests {
    private func signedIn(_ responses: [(Int, String)]) -> (AppModel, StubTransport) {
        let http = StubTransport(responses)
        let stored = TokenSet(accessToken: "AT", refreshToken: "RT", idToken: nil, expiresAt: .distantFuture)
        let session = AuthSession(config: config, store: InMemoryTokenStore(stored), http: http)
        return (AppModel(session: session, http: http), http)
    }

    @Test func completingTheRegistrationPutsTheBirthDate() async throws {
        let (app, http) = signedIn([(200, #"{"id":"u1","userName":"robin","birthDate":"1995-03-12","registrationCompleted":true}"#)])
        let profile = try await app.users.completeRegistration(birthDate: "1995-03-12")
        #expect(profile.birthDate == "1995-03-12")
        #expect(profile.registrationCompleted)
        #expect(http.requests[0].httpMethod == "PUT")
        #expect(http.requests[0].url?.path() == "/api/v1/user-service/profile/registration")
        #expect(String(data: http.requests[0].httpBody ?? Data(), encoding: .utf8) == #"{"birthDate":"1995-03-12"}"#)
    }

    @Test func birthdaysAreAskedForARange() async throws {
        let (app, http) = signedIn([(200, #"[{"userId":"u1","name":"Léa","date":"2026-10-20","closeness":"INTIMATE","canOrganize":true},{"broken":true}]"#)])
        let from = try Date("2026-09-28T00:00:00Z", strategy: .iso8601)
        let to = try Date("2026-11-02T00:00:00Z", strategy: .iso8601)
        let list = try await app.events.birthdays(from: from, to: to)
        #expect(list.map(\.name) == ["Léa"])
        #expect(list.first?.canOrganize == true)
        let url = try #require(http.requests[0].url)
        #expect(url.path() == "/api/v1/events-service/events/me/birthdays")
        #expect(url.query()?.contains("from=2026-09-28T00:00:00Z") == true)
        #expect(url.query()?.contains("to=2026-11-02T00:00:00Z") == true)
    }

    @Test func aSecondSurpriseNamesTheExistingOne() async {
        let (app, _) = signedIn([(409, #"{"code":"EVT-BUS-030","detail":"exists","eventId":"e42"}"#)])
        let request = EventCreateRequest(title: "Surprise", startDate: .now, location: "", kind: .surprise, honoreeId: "lea")
        do {
            _ = try await app.events.create(request)
            Issue.record("a 409 was expected")
        } catch let error as APIError {
            #expect(error.status == 409)
            #expect(error.eventId == "e42")
            #expect(error.code == "EVT-BUS-030")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func aSurpriseIsSentWithItsKindAndHonoree() throws {
        let request = EventCreateRequest(title: "S", startDate: try Date("2026-11-03T18:00:00Z", strategy: .iso8601), location: "",
                                         allDay: nil, kind: .surprise, honoreeId: "lea")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.wely.encode(request)) as? [String: Any])
        #expect(object["kind"] as? String == "SURPRISE")
        #expect(object["honoreeId"] as? String == "lea")
        #expect(object["allDay"] == nil)
    }

    @Test func calendarLinksGoToTheCalendarTab() {
        let (app, _) = signedIn([])
        app.selectedTab = .social
        app.open(.surprise(honoreeId: "lea", date: "2026-11-03"))
        #expect(app.selectedTab == .calendar)
        #expect(app.calendarRequest == .surprise(honoreeId: "lea", date: "2026-11-03"))
        #expect(app.pendingDestination == nil)
    }
}
