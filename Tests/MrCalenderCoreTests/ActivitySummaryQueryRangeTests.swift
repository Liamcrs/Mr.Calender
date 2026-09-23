import XCTest
@testable import MrCalenderCore

final class ActivitySummaryQueryRangeTests: XCTestCase {
    func testBothPredicateBoundsCarryGregorianCalendarAndCallerTimeZone() {
        var caller = Calendar(identifier: .buddhist)
        caller.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let range = ActivitySummaryQueryRange(
            from: ISO8601DateFormatter().date(from: "2026-12-24T15:00:00Z")!,
            to: ISO8601DateFormatter().date(from: "2026-12-27T15:00:00Z")!,
            calendar: caller
        )

        XCTAssertEqual(range.calendar.identifier, .gregorian)
        XCTAssertEqual(range.calendar.timeZone, caller.timeZone)
        for (bound, day) in [(range.start, 25), (range.end, 28)] {
            XCTAssertEqual(bound.calendar, range.calendar)
            XCTAssertEqual(bound.timeZone, caller.timeZone)
            XCTAssertEqual(bound.era, 1)
            XCTAssertEqual(bound.year, 2026)
            XCTAssertEqual(bound.month, 12)
            XCTAssertEqual(bound.day, day)
            XCTAssertNotNil(bound.date)
        }
    }

    func testPredicateBoundsPreserveLocalDatesAcrossDaylightSavingChange() {
        var caller = Calendar(identifier: .gregorian)
        caller.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = ISO8601DateFormatter().date(from: "2026-03-07T08:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-03-10T07:00:00Z")!
        let range = ActivitySummaryQueryRange(from: start, to: end, calendar: caller)

        XCTAssertEqual(range.start.date, start)
        XCTAssertEqual(range.end.date, end)
        XCTAssertEqual(range.start.day, 7)
        XCTAssertEqual(range.end.day, 10)
        XCTAssertEqual(range.start.timeZone, caller.timeZone)
        XCTAssertEqual(range.end.timeZone, caller.timeZone)
    }
}
