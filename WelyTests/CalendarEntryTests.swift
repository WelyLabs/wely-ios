import Foundation
import Testing
@testable import Wely

struct CalendarEntryTests {
    private let calendar = Calendar.wely
    private func date(_ day: Int, _ hour: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func fixedEventsAndPollSlotsAreMergedAndSorted() {
        let fixed = FeedEvent(id: "a", title: "Fixe", organizerId: "me", startDate: date(15, 19))
        let poll = FeedEvent(id: "p", title: "Sondage", organizerId: "lea", startDate: date(20, 20), poll: Poll(status: .open, slots: [
            PollSlot(id: "s2", start: date(21, 20), end: date(21, 22)),
            PollSlot(id: "s1", start: date(14, 20), end: date(14, 22)),
        ]))
        // The open poll arrives twice (subscribed and polls) but shows once per slot.
        let entries = CalendarEntry.make(subscribed: [fixed, poll], polls: [poll], myId: "me")

        #expect(entries.map(\.id) == ["p#s1", "a", "p#s2"])
        #expect(entries.map(\.tentative) == [true, false, true])
        #expect(entries.map(\.mine) == [false, true, false])
    }

    @Test func aClosedPollIsAFixedEvent() {
        let closed = FeedEvent(id: "c", title: "Fixé", organizerId: "x", startDate: date(15, 19),
                               poll: Poll(status: .closed, fixedSlotId: "s", slots: [PollSlot(id: "s", start: date(15, 19), end: date(15, 21))]))
        let entries = CalendarEntry.make(subscribed: [closed], polls: [], myId: nil)
        #expect(entries.map(\.id) == ["c"])
        #expect(entries.first?.mine == false)
    }

    @Test func anEventAcrossMidnightShowsOnBothDays() {
        let late = CalendarEntry(event: FeedEvent(id: "n", title: "Nuit", organizerId: "x", startDate: date(15, 22)),
                                 start: date(15, 22), end: date(16, 2), slotId: nil, mine: false)
        #expect(late.occurs(on: date(15), calendar: calendar))
        #expect(late.occurs(on: date(16), calendar: calendar))
        #expect(!late.occurs(on: date(17), calendar: calendar))
    }

    @Test func anEventEndingAtMidnightStaysOnItsDay() {
        let entry = CalendarEntry(event: FeedEvent(id: "m", title: "M", organizerId: "x", startDate: date(15, 20)),
                                  start: date(15, 20), end: date(16, 0), slotId: nil, mine: false)
        #expect(entry.occurs(on: date(15), calendar: calendar))
        #expect(!entry.occurs(on: date(16), calendar: calendar))
    }

    @Test func anAllDayEventShowsOnItsUTCDaysInAnyTimeZone() throws {
        let start = try Date("2026-03-12T00:00:00Z", strategy: .iso8601)
        let event = FeedEvent(id: "a", title: "A", organizerId: "x", startDate: start, endDate: start.addingTimeInterval(86_400), allDay: true)
        let entry = try #require(CalendarEntry.make(subscribed: [event], polls: [], myId: nil).first)
        #expect(entry.isAllDay)
        for zone in ["Europe/Paris", "America/Los_Angeles", "Pacific/Auckland"] {
            var local = Calendar.wely
            local.timeZone = TimeZone(identifier: zone)!
            let day = { (d: Int) in local.date(from: DateComponents(year: 2026, month: 3, day: d, hour: 12))! }
            #expect(!entry.occurs(on: day(11), calendar: local), "\(zone)")
            #expect(entry.occurs(on: day(12), calendar: local), "\(zone)")
            #expect(!entry.occurs(on: day(13), calendar: local), "\(zone)")
        }
    }

    @Test func aSeveralDayAllDayEventCoversEachDay() throws {
        let start = try Date("2026-03-12T00:00:00Z", strategy: .iso8601)
        let event = FeedEvent(id: "w", title: "W", organizerId: "x", startDate: start, endDate: start.addingTimeInterval(3 * 86_400), allDay: true)
        let entry = CalendarEntry(event: event, start: event.startDate, end: event.endDate, slotId: nil, mine: false)
        let days = (10...16).filter { entry.occurs(on: calendar.date(from: DateComponents(year: 2026, month: 3, day: $0))!, calendar: calendar) }
        #expect(days == [12, 13, 14])
    }

    @Test func birthdayEventsStayOutOfTheEntries() {
        let birthday = FeedEvent(id: "b", title: "Anniversaire", organizerId: "lea", startDate: date(15), allDay: true, kind: .birthday)
        let surprise = FeedEvent(id: "s", title: "Surprise", organizerId: "me", startDate: date(15, 19), kind: .surprise, honoreeId: "lea")
        #expect(CalendarEntry.make(subscribed: [birthday, surprise], polls: [], myId: "me").map(\.id) == ["s"])
    }

    @Test func monthGridStartsOnMondayInWholeWeeks() {
        // October 2026 starts on a Thursday: three September days lead.
        let grid = MonthGrid(containing: date(15), calendar: calendar)
        #expect(grid.days.count == 35)
        #expect(grid.days.first?.date == date(28, month: 9))
        #expect(grid.days.first?.isCurrentMonth == false)
        #expect(grid.days[3].date == date(1))
        #expect(grid.days.filter(\.isCurrentMonth).count == 31)
        #expect(MonthGrid.weekdaySymbols(calendar: calendar) == ["L", "M", "M", "J", "V", "S", "D"])
    }
}
