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
    /// The birthdays of the shown grid, by « YYYY-MM-DD ».
    private(set) var birthdays: [String: [BirthdayOccurrence]] = [:]
    private(set) var phase: Phase = .loading
    /// The intimate friends' entries over the shown grid, while « Mon cercle » is on.
    private(set) var circle: [CircleEntry] = []
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

    var selectedBirthdays: [BirthdayOccurrence] { birthdays(on: selectedDay) }

    /// The user's own first, then friends from the closest.
    func birthdays(on day: Date) -> [BirthdayOccurrence] {
        (birthdays[DayString.string(from: day, calendar: calendar)] ?? []).sorted { ($0.style, $1.name) > ($1.style, $0.name) }
    }

    /// The birthdays of the grid on screen; a failure keeps the calendar without them.
    func loadBirthdays() async {
        let days = grid.days
        guard let first = days.first?.date, let last = days.last?.date,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        guard let list = try? await events.birthdays(from: first, to: end) else { return }
        birthdays = Dictionary(grouping: list, by: \.date)
    }

    var selectedCircle: [CircleEntry] { circleEntries(on: selectedDay) }

    /// By start, then by friend.
    func circleEntries(on day: Date) -> [CircleEntry] {
        circle.filter { $0.occurs(on: day, calendar: calendar) }.sorted { ($0.allDay ? 0 : 1, $0.start, $0.userId) < ($1.allDay ? 0 : 1, $1.start, $1.userId) }
    }

    /// The intimates' calendars over the grid on screen (six weeks at most); a failure leaves it empty.
    func loadCircle() async {
        let days = grid.days
        guard let first = days.first?.date, let last = days.last?.date,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        circle = (try? await events.circle(from: first, to: end)) ?? []
    }

    func clearCircle() { circle = [] }

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

    /// Selects a « YYYY-MM-DD » day from a link.
    func select(dayString: String) {
        if let day = DayString.date(from: dayString, calendar: calendar) { select(day) }
    }

    func select(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        if !calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = calendar.dateInterval(of: .month, for: day)!.start
        }
    }
}
