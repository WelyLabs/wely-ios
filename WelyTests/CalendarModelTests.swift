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
    /// The real day, because the demo fixture these tests read is built on the wall clock too, and
    /// CalendarModel's own `goToToday()` reads it. Pinned to a date it drifted away from, this was a
    /// fuse: 2026-10-15 agreed with reality until 1 November 2026, then three expectations went red.
    private var today: Date { calendar.startOfDay(for: .now) }

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
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: today)!

        model.showMonth(offset: 1)
        #expect(calendar.isDate(model.displayedMonth, equalTo: nextMonth, toGranularity: .month))
        // Next month never holds today, so the selection falls on its first day.
        #expect(calendar.component(.day, from: model.selectedDay) == 1)

        model.goToToday()
        #expect(calendar.isDate(model.displayedMonth, equalTo: today, toGranularity: .month))
        #expect(calendar.isDate(model.selectedDay, inSameDayAs: today))
    }

    @Test func selectingADayOfAnotherMonthShowsThatMonth() {
        let model = model()
        let nextMonthDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        model.select(nextMonthDay)
        #expect(calendar.component(.month, from: model.displayedMonth) == 11)
        #expect(model.selectedDay == nextMonthDay)
    }
}
