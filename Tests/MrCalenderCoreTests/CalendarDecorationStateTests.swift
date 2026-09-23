import XCTest
@testable import MrCalenderCore

final class CalendarDecorationStateTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }

    private func event(_ timestamp: String, source: EventSource = .custom) -> CalendarEvent {
        let start = ISO8601DateFormatter().date(from: timestamp + "+09:00")!
        return CalendarEvent(title: "事项", startsAt: start,
                             endsAt: start.addingTimeInterval(3600), source: source)
    }

    private func state(_ events: [CalendarEvent]) -> CalendarDecorationState {
        var snapshot = AppSnapshot()
        let timetable = Timetable(name: "主课表")
        snapshot.timetables = [timetable]
        snapshot.events = events.map { event in
            var value = event
            if value.source == .course { value.timetableID = timetable.id }
            return value
        }
        return CalendarDecorationState(snapshot: snapshot, calendar: calendar)
    }

    private func reloads(_ new: [CalendarEvent], after old: [CalendarEvent]) -> [DateComponents] {
        state(new).datesToReload(
            comparedTo: state(old),
            visibleMonth: DateComponents(year: 2026, month: 9),
            calendar: calendar
        )
    }

    func testOnlyChangedDayCategorySetsInVisibleMonthReload() {
        let unchanged = event("2026-09-02T10:00:00")
        let oldDay = event("2026-09-04T10:00:00")
        let newDay = event("2026-09-05T10:00:00")
        let offscreen = event("2026-10-04T10:00:00")
        let result = reloads([unchanged, newDay, offscreen], after: [unchanged, oldDay])

        XCTAssertEqual(result.map(\.day), [4, 5])
        XCTAssertTrue(result.allSatisfy { $0.year == 2026 && $0.month == 9 })
    }

    func testRemovingOneCategoryReloadsOnlyThatDay() {
        let course = event("2026-09-04T10:00:00", source: .course)
        let custom = event("2026-09-04T14:00:00")
        let unchanged = event("2026-09-05T10:00:00")
        XCTAssertEqual(reloads([custom, unchanged], after: [course, custom, unchanged]).map(\.day), [4])
    }

    func testDuplicateCategoryAndNonvisualEditsDoNotReload() {
        let original = event("2026-09-04T10:00:00")
        var edited = original
        edited.title = "改名"
        edited.startsAt = original.startsAt.addingTimeInterval(3600)
        let duplicate = event("2026-09-04T15:00:00")
        XCTAssertEqual(reloads([edited, duplicate], after: [original]), [])
    }

    func testOffscreenChangesWaitUntilTheirMonthIsShown() {
        let old = event("2026-10-04T10:00:00")
        let new = event("2027-09-04T10:00:00")
        XCTAssertEqual(reloads([new], after: [old]), [])
    }

    func testConfigurationChangeReloadsHolidayOnlyAndEmptyCells() {
        let empty = state([])
        let result = empty.datesToReload(
            comparedTo: empty,
            visibleMonth: DateComponents(year: 2026, month: 9),
            calendar: calendar,
            configurationChanged: true
        )
        XCTAssertEqual(result.map(\.day), Array(1...30))
        XCTAssertTrue(result.allSatisfy { $0.year == 2026 && $0.month == 9 })
        let holiday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        XCTAssertEqual(CalendarIndicators.indicators(on: holiday, snapshot: AppSnapshot(), calendar: calendar), [.holiday])
        XCTAssertTrue(result.contains { $0.day == 25 })
    }

    func testConfigurationReloadRespectsLeapMonthLength() {
        let empty = state([])
        let result = empty.datesToReload(
            comparedTo: empty,
            visibleMonth: DateComponents(year: 2028, month: 2),
            calendar: calendar,
            configurationChanged: true
        )
        XCTAssertEqual(result.map(\.day), Array(1...29))
        XCTAssertTrue(result.allSatisfy { $0.year == 2028 && $0.month == 2 })
    }
}
