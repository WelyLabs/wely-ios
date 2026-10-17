import EventKit
import Foundation

/// An event into the user's own agenda: the iPhone's Calendar (and every account it syncs,
/// iCloud, Google, Outlook) through EventKit, or Google Calendar's « add event » page. A copy,
/// not a sync, as on wely-web.
enum CalendarExport {
    /// The event's page on the web front, which the agenda's copy links back to.
    static func eventURL(_ event: FeedEvent, config: AppConfig = .current) -> URL {
        config.webURL.appending(path: "event/\(event.id)")
    }

    /// The organizer's words, then the way back to the event.
    static func notes(_ event: FeedEvent, eventURL: URL) -> String {
        event.description.isEmpty ? eventURL.absoluteString : "\(event.description)\n\n\(eventURL.absoluteString)"
    }

    /// 2026-10-17 18:30 UTC → « 20261017T183000Z ».
    static func utcStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// Google Calendar's « add event » page, filled in; it opens the Google Calendar app when installed.
    static func googleCalendarURL(_ event: FeedEvent, eventURL: URL) -> URL {
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: event.title),
            URLQueryItem(name: "dates", value: "\(utcStamp(event.startDate))/\(utcStamp(event.endDate))"),
            URLQueryItem(name: "details", value: notes(event, eventURL: eventURL)),
            URLQueryItem(name: "location", value: event.location)
        ]
        return components.url!
    }

    /// The event as the system's editor shows it, for the user to check and add.
    static func calendarEvent(_ event: FeedEvent, eventURL: URL, store: EKEventStore) -> EKEvent {
        let copy = EKEvent(eventStore: store)
        copy.title = event.title
        copy.startDate = event.startDate
        copy.endDate = event.endDate
        copy.location = event.location.isEmpty ? nil : event.location
        copy.notes = notes(event, eventURL: eventURL)
        copy.url = eventURL
        if let coordinates = event.coordinates {
            let place = EKStructuredLocation(title: event.location)
            place.geoLocation = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
            copy.structuredLocation = place
        }
        return copy
    }
}
