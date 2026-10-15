import Foundation
import Testing
@testable import Wely

struct WireDateTests {
    private func decode(_ json: String) throws -> Date {
        struct Box: Decodable { let date: Date }
        return try JSONDecoder.wely.decode(Box.self, from: Data("{\"date\": \(json)}".utf8)).date
    }

    @Test func readsAnInstantWithoutFraction() throws {
        let date = try decode("\"2026-10-15T17:00:00Z\"")
        #expect(date == Date(timeIntervalSince1970: 1_792_083_600))
    }

    @Test func readsAnInstantWithFraction() throws {
        let date = try decode("\"2026-10-15T17:00:00.123Z\"")
        #expect(abs(date.timeIntervalSince1970 - 1_792_083_600.123) < 0.001)
    }

    @Test func readsAZonelessDateTimeAsLocalTime() throws {
        let date = try decode("\"2026-10-15T19:30:00\"")
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts == DateComponents(year: 2026, month: 10, day: 15, hour: 19, minute: 30))
    }

    @Test func readsAnArrayAsLocalTimeWithOneBasedMonth() throws {
        let date = try decode("[2026, 10, 15, 19, 30]")
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(parts == DateComponents(year: 2026, month: 10, day: 15, hour: 19, minute: 30, second: 0))
    }

    @Test func rejectsGarbage() {
        #expect(throws: DecodingError.self) { try decode("\"pas une date\"") }
    }

    @Test func rejectsATooShortArray() {
        #expect(WireDate.from(components: [2026, 10]) == nil)
    }
}
