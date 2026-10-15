import Foundation
import Observation

/// The calendar screen's state: which month, which day, and the user's entries.
@Observable
final class CalendarModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var entries: [CalendarEntry] = []
    private(set) var phase: Phase = .loading
    var displayedMonth: Date
    var selectedDay: Date

    let calendar: Calendar
    @ObservationIgnored private let events: EventService
    @ObservationIgnored private let myId: () -> String?

    init(events: EventService, myId: @escaping () -> String?, calendar: Calendar = .wely, today: Date = .now) {
        self.events = events
        self.myId = myId
        self.calendar = calendar
        self.displayedMonth = calendar.dateInterval(of: .month, for: today)!.start
        self.selectedDay = calendar.startOfDay(for: today)
    }

    var grid: MonthGrid { MonthGrid(containing: displayedMonth, calendar: calendar) }

    var selectedEntries: [CalendarEntry] { entries(on: selectedDay) }

    func entries(on day: Date) -> [CalendarEntry] {
        entries.filter { $0.occurs(on: day, calendar: calendar) }
    }

    /// Loads the user's events and open polls; a failing poll list leaves the fixed events
    /// shown, as on the web.
    func load() async {
        if entries.isEmpty { phase = .loading }
        do {
            let subscribed = try await events.subscribed()
            let polls = (try? await events.myPolls()) ?? []
            entries = CalendarEntry.make(subscribed: subscribed, polls: polls, myId: myId())
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func showMonth(offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = month
        // Keep the selection in view: today when it is in that month, its first day otherwise.
        let today = calendar.startOfDay(for: .now)
        selectedDay = calendar.isDate(today, equalTo: month, toGranularity: .month) ? today : month
    }

    func goToToday() {
        let today = calendar.startOfDay(for: .now)
        displayedMonth = calendar.dateInterval(of: .month, for: today)!.start
        selectedDay = today
    }

    func select(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        if !calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = calendar.dateInterval(of: .month, for: day)!.start
        }
    }
}
