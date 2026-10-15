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
        // 6 fixed events joined + 2 slots of the open poll.
        #expect(model.entries.count == 8)
        #expect(model.selectedEntries.map(\.title) == ["Afterwork au Ninkasi"])
        #expect(model.selectedEntries.first?.mine == true)
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
