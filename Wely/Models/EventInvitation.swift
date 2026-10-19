import Foundation

/// An invitation to an event, as it travels in a direct message: a link to the event's page,
/// marked so the chat tells it from a plain share. The same words and link as wely-web sends.
enum EventInvitation {
    static let marker = "invitation"

    /// `…/event/<id>?invitation` on the web front.
    static func link(eventId: String, config: AppConfig = .current) -> URL {
        config.webURL.appending(path: "event/\(eventId)").appending(queryItems: [URLQueryItem(name: marker, value: nil)])
    }

    /// The event an invitation message links to, from any origin.
    static func eventId(in text: String?) -> String? {
        guard let text, let match = text.firstMatch(of: /\/event\/([A-Za-z0-9_-]+)\?invitation\b/) else { return nil }
        return String(match.1)
    }

    /// The words before the link, without the colon that introduced it.
    static func intro(of text: String) -> String {
        guard let range = text.range(of: #"https?://|/event/"#, options: .regularExpression) else { return text }
        return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces).replacing(/\s*:\s*$/, with: "")
    }

    static func message(for event: FeedEvent, config: AppConfig = .current) -> String {
        "Je t'invite à « \(event.title) »\(when(event)) sur Wely : \(link(eventId: event.id, config: config).absoluteString)"
    }

    /// « le samedi 25 octobre à 20:00 », or nothing while the date is voted on.
    static func when(_ event: FeedEvent, timeZone: TimeZone = .current) -> String {
        if event.isOpenPoll { return "" }
        let day = DateFormatter()
        day.locale = Locale(identifier: "fr_FR")
        day.dateFormat = "EEEE d MMMM"
        if event.allDay {
            day.timeZone = TimeZone(identifier: "UTC")
            return " le \(day.string(from: event.startDate))"
        }
        day.timeZone = timeZone
        let time = DateFormatter()
        time.locale = Locale(identifier: "fr_FR")
        time.timeZone = timeZone
        time.dateFormat = "HH:mm"
        return " le \(day.string(from: event.startDate)) à \(time.string(from: event.startDate))"
    }
}
