import EventKit
import Foundation
import Testing
@testable import Wely

struct CalendarExportTests {
    private let start = Date(timeIntervalSince1970: 1_792_863_000) // 2026-10-24 17:30 UTC
    private let pageURL = URL(string: "https://web.welylabs.app/event/e1")!

    private func event(description: String = "", coordinates: Coordinates? = nil) -> FeedEvent {
        FeedEvent(id: "e1", title: "Apéro chez Léa", organizerId: "u1", startDate: start,
                  endDate: start.addingTimeInterval(3.5 * 3600), location: "Lyon", coordinates: coordinates,
                  description: description)
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func linksBackToTheEventPageOnTheWebFront() {
        let config = AppConfig(gatewayURL: URL(string: "https://gw")!, keycloakURL: URL(string: "https://kc")!,
                               webURL: URL(string: "https://dev-web.welylabs.app")!)
        #expect(CalendarExport.eventURL(event(), config: config).absoluteString == "https://dev-web.welylabs.app/event/e1")
    }

    @Test func writesTheBasicUtcForm() {
        #expect(CalendarExport.utcStamp(start) == "20261024T173000Z")
    }

    @Test func fillsGoogleCalendarsAddEventPage() {
        let url = CalendarExport.googleCalendarURL(event(description: "Ramène des chips"), eventURL: pageURL)
        let items = query(url)

        #expect(url.host() == "calendar.google.com")
        #expect(url.path() == "/calendar/render")
        #expect(items["action"] == "TEMPLATE")
        #expect(items["text"] == "Apéro chez Léa")
        #expect(items["dates"] == "20261024T173000Z/20261024T210000Z")
        #expect(items["location"] == "Lyon")
        #expect(items["details"] == "Ramène des chips\n\nhttps://web.welylabs.app/event/e1")
    }

    @Test func notesAreTheLinkAloneWithoutDescription() {
        #expect(CalendarExport.notes(event(), eventURL: pageURL) == "https://web.welylabs.app/event/e1")
    }

    @Test func fillsTheSystemEditorsEvent() {
        let copy = CalendarExport.calendarEvent(event(description: "Ramène des chips"), eventURL: pageURL, store: EKEventStore())

        #expect(copy.title == "Apéro chez Léa")
        #expect(copy.startDate == start)
        #expect(copy.endDate == start.addingTimeInterval(3.5 * 3600))
        #expect(copy.location == "Lyon")
        #expect(copy.notes == "Ramène des chips\n\nhttps://web.welylabs.app/event/e1")
        #expect(copy.url == pageURL)
        #expect(copy.structuredLocation?.geoLocation == nil)
    }

    @Test func placesAPickedLocationOnTheMap() {
        let copy = CalendarExport.calendarEvent(event(coordinates: Coordinates(latitude: 45.764, longitude: 4.8357)),
                                                eventURL: pageURL, store: EKEventStore())

        #expect(copy.structuredLocation?.title == "Lyon")
        #expect(copy.structuredLocation?.geoLocation?.coordinate.latitude == 45.764)
        #expect(copy.structuredLocation?.geoLocation?.coordinate.longitude == 4.8357)
    }
}
