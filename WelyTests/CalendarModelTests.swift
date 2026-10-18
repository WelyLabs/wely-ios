import Foundation
import Testing
@testable import Wely

/// Answers every request with a 502.
private final class FailingTransport: HTTPTransport, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(), HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!)
    }
}

struct CalendarModelTests {
    private let calendar = Calendar.wely
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))! }

    private func model(_ http: HTTPTransport = DemoTransport()) -> CalendarModel {
        let session = AuthSession(store: InMemoryTokenStore(TokenSet(accessToken: "t", refreshToken: nil, idToken: nil, expiresAt: .distantFuture)))
        return CalendarModel(events: EventService(api: APIClient(session: session, http: http)), myId: { DemoStore.me }, calendar: calendar, today: today)
    }

    @Test func loadsTheDemoEntriesAndMarksMine() async {
        let model = model()
        model.goToToday()
        await model.load()

        #expect(model.phase == .loaded)
        // 7 fixed events joined (one all-day) + 2 slots of the open poll.
        #expect(model.entries.count == 9)
        #expect(model.entries.filter(\.isAllDay).map(\.title) == ["Fête des Lumières"])
        #expect(model.selectedEntries.map(\.title) == ["Afterwork au Ninkasi"])
        #expect(model.selectedEntries.first?.mine == true)
    }

    @Test func loadsTheCircleOfTheGridAndClearsIt() async {
        let model = model()
        model.select(Calendar.wely.date(byAdding: .day, value: 1, to: .now)!)
        await model.loadCircle()
        #expect(!model.circle.isEmpty)
        #expect(model.selectedCircle.contains { $0.title == nil && $0.userId == "lea" })
        model.clearCircle()
        #expect(model.circle.isEmpty)
    }

    @Test func aFailingCircleLeavesItEmpty() async {
        let model = model(FailingTransport())
        await model.loadCircle()
        #expect(model.circle.isEmpty)
    }

    @Test func loadsTheBirthdaysOfTheGrid() async {
        let model = model()
        model.goToToday()
        await model.loadBirthdays()
        let today = model.birthdays(on: model.selectedDay)
        #expect(today.map(\.style) == [.mine])

        // Hugo, in 9 days, already has a surprise: no second one.
        model.select(calendar.date(byAdding: .day, value: 9, to: .now)!)
        await model.loadBirthdays()
        let hugo = model.selectedBirthdays.first { $0.userId == "hugo" }
        #expect(hugo?.surprise?.eventId == "demo-surprise")
        #expect(hugo?.canOrganize == false)
        #expect(hugo?.style == .close)
    }

    @Test func aDayFromALinkIsSelected() {
        let model = model()
        model.select(dayString: "2026-12-24")
        #expect(calendar.component(.month, from: model.displayedMonth) == 12)
        #expect(calendar.component(.day, from: model.selectedDay) == 24)
    }

    @Test func aFailureIsReported() async {
        let model = model(FailingTransport())
        await model.load()
        #expect(model.phase == .failed("Le serveur Wely ne répond pas (502)."))
        #expect(model.entries.isEmpty)
    }

    @Test func navigatesBetweenMonths() {
        let model = model()
        model.showMonth(offset: 1)
        #expect(calendar.component(.month, from: model.displayedMonth) == 11)
        #expect(calendar.component(.day, from: model.selectedDay) == 1)

        model.goToToday()
        #expect(calendar.isDate(model.displayedMonth, equalTo: .now, toGranularity: .month))
        #expect(calendar.isDateInToday(model.selectedDay))
    }

    @Test func selectingADayOfAnotherMonthShowsThatMonth() {
        let model = model()
        let nextMonthDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        model.select(nextMonthDay)
        #expect(calendar.component(.month, from: model.displayedMonth) == 11)
        #expect(model.selectedDay == nextMonthDay)
    }
}
