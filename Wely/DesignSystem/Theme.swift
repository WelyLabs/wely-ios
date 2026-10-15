import SwiftUI

/// Wely's colours: the blue → orange of the web app's accent gradient.
nonisolated enum Theme {
    static let blue = Color(red: 0.231, green: 0.424, blue: 0.965)
    static let orange = Color(red: 1.0, green: 0.541, blue: 0.239)

    static let gradient = LinearGradient(colors: [blue, orange], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// An entry's colour: blue for the user's own events, orange for friends', grey for a proposed date.
    @MainActor static func color(for entry: CalendarEntry) -> Color {
        if entry.tentative { return .secondary }
        return entry.mine ? blue : orange
    }
}

extension Date {
    /// « 19:00 – 22:00 », the 24-hour clock read in France.
    static func timeRange(_ start: Date, _ end: Date) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

extension Locale {
    static let wely = Locale(identifier: "fr_FR")
}
