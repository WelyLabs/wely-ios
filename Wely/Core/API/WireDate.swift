import Foundation

/// Reads a date as the backend sends it.
///
/// Spring serialises `Instant` as an ISO string, with or without fractional seconds, and a
/// `LocalDateTime` either as a zoneless ISO string or, depending on the Jackson configuration,
/// as a `[year, month, day, hour, minute, second, nanos]` array in local time — the same shapes
/// wely-web's `toDate` accepts.
nonisolated enum WireDate {
    static func parse(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
        if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
        return localFormatters.lazy.compactMap { $0.date(from: string) }.first
    }

    static func from(components values: [Int], calendar: Calendar = .current) -> Date? {
        guard values.count >= 3 else { return nil }
        var parts = DateComponents()
        parts.year = values[0]
        parts.month = values[1]
        parts.day = values[2]
        parts.hour = values.count > 3 ? values[3] : 0
        parts.minute = values.count > 4 ? values[4] : 0
        parts.second = values.count > 5 ? values[5] : 0
        parts.nanosecond = values.count > 6 ? values[6] : 0
        return calendar.date(from: parts)
    }

    /// A zoneless date-time is the device's local time.
    private static let localFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}

extension JSONDecoder {
    /// The decoder for every gateway answer.
    static var wely: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let values = try? container.decode([Int].self), let date = WireDate.from(components: values) {
                return date
            }
            if let string = try? container.decode(String.self), let date = WireDate.parse(string) {
                return date
            }
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable date")
        }
        return decoder
    }
}
