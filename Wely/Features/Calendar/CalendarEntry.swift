import Foundation

/// One line of the calendar: a fixed event, or one proposed slot of an open date poll.
struct CalendarEntry: Hashable, Identifiable, Sendable {
    let event: FeedEvent
    let start: Date
    let end: Date
    /// The proposed slot, for an open poll: shown « ? », not a firm event.
    let slotId: String?
    /// True when the signed-in user organizes the event, false when they joined a friend's.
    let mine: Bool

    var id: String { slotId.map { "\(event.id)#\($0)" } ?? event.id }
    var tentative: Bool { slotId != nil }
    var title: String { event.title }

    /// Fixed events as they are; each open poll as one tentative entry per proposed slot,
    /// polls deduplicated — as wely-web's `toCalendarEvents`.
    static func make(subscribed: [FeedEvent], polls: [FeedEvent], myId: String?) -> [CalendarEntry] {
        let isMine = { (event: FeedEvent) in myId != nil && event.organizerId == myId }

        let fixed = subscribed
            .filter { !$0.isOpenPoll }
            .map { CalendarEntry(event: $0, start: $0.startDate, end: $0.endDate, slotId: nil, mine: isMine($0)) }

        var seen = Set<String>()
        let openPolls = (subscribed + polls).filter { $0.isOpenPoll && seen.insert($0.id).inserted }
        let tentative = openPolls.flatMap { event in
            (event.poll?.slots ?? []).map {
                CalendarEntry(event: event, start: $0.start, end: $0.end, slotId: $0.id, mine: isMine(event))
            }
        }
        return (fixed + tentative).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// True when the entry overlaps the day, so an event across midnight shows on both days.
    func occurs(on day: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return start < dayEnd && max(end, start.addingTimeInterval(1)) > dayStart
    }
}

/// The days a month view shows: whole weeks, Monday first in French, padded with the
/// neighbouring months' days.
struct MonthGrid: Sendable {
    struct Day: Hashable, Identifiable, Sendable {
        let date: Date
        let isCurrentMonth: Bool
        var id: Date { date }
    }

    let month: Date
    let days: [Day]

    init(containing date: Date, calendar: Calendar) {
        let interval = calendar.dateInterval(of: .month, for: date)!
        month = interval.start
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: interval.start)!.count
        let cells = Int((Double(leading + daysInMonth) / 7).rounded(.up)) * 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: interval.start)!

        days = (0..<cells).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            return Day(date: day, isCurrentMonth: calendar.isDate(day, equalTo: interval.start, toGranularity: .month))
        }
    }

    /// The weekday initials in grid order: « L M M J V S D » in French.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

extension Calendar {
    /// The calendar the app reasons in: French, weeks from Monday.
    static var wely: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }
}
