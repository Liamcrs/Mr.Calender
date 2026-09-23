import XCTest
@testable import MrCalenderCore

final class CalendarIndicatorTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+08:00")!
    }

    func testIndicatorsUseStableHolidayCourseCustomOrderAndCollapseDuplicates() {
        let day = date("2026-10-01T09:00:00")
        var snapshot = AppSnapshot()
        let timetable = Timetable(name: "主课表")
        snapshot.timetables = [timetable]
        snapshot.events = [
            CalendarEvent(title: "高数", startsAt: day, endsAt: day.addingTimeInterval(3600), source: .course, timetableID: timetable.id),
            CalendarEvent(title: "英语", startsAt: day.addingTimeInterval(7200), endsAt: day.addingTimeInterval(10800), source: .course, timetableID: timetable.id),
            CalendarEvent(title: "交作业", startsAt: day, endsAt: day.addingTimeInterval(1800), source: .custom)
        ]

        XCTAssertEqual(
            CalendarIndicators.indicators(on: day, snapshot: snapshot, calendar: calendar),
            [.holiday, .course, .customEvent]
        )
    }

    func testDisabledTimetableDoesNotProduceCourseIndicator() {
        let day = date("2026-09-23T09:00:00")
        let timetable = Timetable(name: "隐藏", isEnabled: false)
        var snapshot = AppSnapshot()
        snapshot.timetables = [timetable]
        snapshot.events = [CalendarEvent(
            title: "隐藏课程",
            startsAt: day,
            endsAt: day.addingTimeInterval(3600),
            source: .course,
            timetableID: timetable.id
        )]

        XCTAssertEqual(
            CalendarIndicators.indicators(on: day, snapshot: snapshot, calendar: calendar),
            []
        )
    }

    func testCourseAndCustomEventsProduceTheirOwnIndicators() {
        let day = date("2026-09-23T09:00:00")
        let timetable = Timetable(name: "主课表")
        var courseSnapshot = AppSnapshot()
        courseSnapshot.timetables = [timetable]
        courseSnapshot.events = [CalendarEvent(
            title: "高数",
            startsAt: day,
            endsAt: day.addingTimeInterval(3600),
            source: .course,
            timetableID: timetable.id
        )]
        var customSnapshot = AppSnapshot()
        customSnapshot.events = [CalendarEvent(
            title: "交作业",
            startsAt: day,
            endsAt: day.addingTimeInterval(1800),
            source: .custom
        )]

        XCTAssertEqual(
            CalendarIndicators.indicators(on: day, snapshot: courseSnapshot, calendar: calendar),
            [.course]
        )
        XCTAssertEqual(
            CalendarIndicators.indicators(on: day, snapshot: customSnapshot, calendar: calendar),
            [.customEvent]
        )
    }

    func testFestivalIsHolidayIndicatorButMakeUpWorkdayIsNot() {
        XCTAssertEqual(
            CalendarIndicators.indicators(
                on: date("2026-12-25T12:00:00"),
                snapshot: AppSnapshot(),
                calendar: calendar
            ),
            [.holiday]
        )
        XCTAssertEqual(
            CalendarIndicators.indicators(
                on: date("2026-09-20T12:00:00"),
                snapshot: AppSnapshot(),
                calendar: calendar
            ),
            []
        )
    }

    func testIndicatorUsesSuppliedCalendarDayBoundary() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let event = CalendarEvent(
            title: "午夜事务",
            startsAt: ISO8601DateFormatter().date(from: "2026-09-23T00:30:00Z")!,
            endsAt: ISO8601DateFormatter().date(from: "2026-09-23T01:00:00Z")!,
            source: .custom
        )
        var snapshot = AppSnapshot()
        snapshot.events = [event]

        XCTAssertEqual(
            CalendarIndicators.indicators(
                on: ISO8601DateFormatter().date(from: "2026-09-23T12:00:00Z")!,
                snapshot: snapshot,
                calendar: utc
            ),
            [.customEvent]
        )
    }
}
