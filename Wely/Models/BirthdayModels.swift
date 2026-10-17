import Foundation

/// A day of the year without its year: what friends see of a birthday.
struct MonthDay: Codable, Hashable, Sendable {
    let month: Int
    let day: Int

    /// « 12 mars ».
    var label: String {
        let date = Calendar.wely.date(from: DateComponents(year: 2000, month: month, day: day)) ?? .now
        return date.formatted(.dateTime.day().month(.wide).locale(.wely))
    }
}

/// One birthday in the calendar, from `events-service/events/me/birthdays`.
struct BirthdayOccurrence: Codable, Hashable, Identifiable, Sendable {
    let userId: String
    let name: String
    /// « 2027-03-12 »: a calendar day, without time zone.
    let date: String
    @DefaultFalse var mine: Bool = false
    /// Nil on the user's own birthday.
    let closeness: Closeness?
    @DefaultFalse var canOrganize: Bool = false
    /// Always nil on the user's own birthday: the surprise stays a surprise.
    let surprise: Surprise?

    struct Surprise: Codable, Hashable, Sendable {
        let eventId: String
        let organizerId: String?
        @DefaultFalse var joined: Bool = false
    }

    init(userId: String, name: String, date: String, mine: Bool = false, closeness: Closeness? = nil,
         canOrganize: Bool = false, surprise: Surprise? = nil) {
        self.userId = userId
        self.name = name
        self.date = date
        self.mine = mine
        self.closeness = closeness
        self.canOrganize = canOrganize
        self.surprise = surprise
    }

    var id: String { "\(userId)#\(date)" }
    var style: BirthdayStyle { BirthdayStyle(self) }

    /// The day in the given calendar, at its start.
    func day(in calendar: Calendar) -> Date? { DayString.date(from: date, calendar: calendar) }

    /// « 12 mars ».
    var dayLabel: String {
        guard let day = day(in: .wely) else { return date }
        return day.formatted(.dateTime.day().month(.wide).locale(.wely))
    }
}

/// How loud a birthday is in the calendar: the user's own, then friends by closeness.
enum BirthdayStyle: Int, Comparable, Sendable {
    case friend, close, intimate, mine

    init(_ occurrence: BirthdayOccurrence) {
        if occurrence.mine { self = .mine; return }
        switch occurrence.closeness {
        case .intimate: self = .intimate
        case .close: self = .close
        case .friend, nil: self = .friend
        }
    }

    var emoji: String {
        switch self {
        case .friend: "🎈"
        case .close: "🎁"
        case .intimate: "💝"
        case .mine: "🎂"
        }
    }

    /// The loudest style of a day's birthdays.
    static func strongest(of occurrences: [BirthdayOccurrence]) -> BirthdayStyle? { occurrences.map(\.style).max() }

    static func < (lhs: BirthdayStyle, rhs: BirthdayStyle) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// « YYYY-MM-DD » days, read and written in a given calendar.
enum DayString {
    static func string(from date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from string: String, calendar: Calendar) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// All-day events run from 00:00Z of their first day to 00:00Z of the day after their last.
enum AllDay {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 00:00Z of the local day `day` falls on.
    static func start(of day: Date, calendar: Calendar) -> Date {
        DayString.date(from: DayString.string(from: day, calendar: calendar), calendar: utc) ?? day
    }

    /// The local day showing the UTC day of `instant`, for date pickers.
    static func localDay(of instant: Date, calendar: Calendar) -> Date {
        DayString.date(from: DayString.string(from: instant, calendar: utc), calendar: calendar) ?? instant
    }

    /// Start and exclusive end of an all-day event from its first and last local days.
    static func range(from first: Date, through last: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = start(of: first, calendar: calendar)
        let lastStart = max(start, self.start(of: last, calendar: calendar))
        return (start, utc.date(byAdding: .day, value: 1, to: lastStart) ?? lastStart)
    }

    /// « Jeudi 12 mars · Toute la journée », or « Du 12 au 14 mars » for several days.
    static func label(_ start: Date, _ end: Date) -> String {
        var style = Date.FormatStyle(locale: .wely, timeZone: TimeZone(identifier: "UTC")!)
        style = style.weekday(.wide).day().month(.wide)
        let lastDay = max(start, end.addingTimeInterval(-86_400))
        if utc.isDate(start, inSameDayAs: lastDay) {
            let day = start.formatted(style)
            return "\(day.prefix(1).uppercased() + day.dropFirst()) · Toute la journée"
        }
        let short = Date.FormatStyle(locale: .wely, timeZone: TimeZone(identifier: "UTC")!).day().month(.wide)
        return "Du \(start.formatted(short)) au \(lastDay.formatted(short))"
    }
}
