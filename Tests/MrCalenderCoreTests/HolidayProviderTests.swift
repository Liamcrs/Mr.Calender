import XCTest
@testable import MrCalenderCore

final class HolidayProviderTests: XCTestCase {
    private func calendar(in timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    func testChristmasUsesTheCallerCivilDateAcrossTimeZones() {
        let tokyo = calendar(in: "Asia/Tokyo")
        let shanghai = calendar(in: "Asia/Shanghai")
        let christmas = ISO8601DateFormatter().date(from: "2026-12-25T00:00:00+09:00")!
        let nextDay = ISO8601DateFormatter().date(from: "2026-12-26T00:00:00+09:00")!
        let christmasLabel = HolidayLabel(name: "圣诞节", kind: .festival)

        XCTAssertEqual(HolidayProvider.labels(on: christmas, calendar: tokyo), [christmasLabel])
        XCTAssertEqual(HolidayProvider.labels(on: nextDay, calendar: tokyo), [])
        XCTAssertEqual(HolidayProvider.labels(on: christmas, calendar: shanghai), [])
        XCTAssertEqual(HolidayProvider.labels(on: nextDay, calendar: shanghai), [christmasLabel])
    }

    func testShanghaiCalendarRetainsChineseHolidaysAndMakeUpWorkdays() {
        let shanghai = calendar(in: "Asia/Shanghai")
        let cases: [(date: String, name: String, kind: HolidayKind)] = [
            ("2026-01-01", "元旦", .holiday),
            ("2026-02-17", "春节", .holiday),
            ("2026-04-05", "清明节", .holiday),
            ("2026-05-01", "劳动节", .holiday),
            ("2026-06-19", "端午节", .holiday),
            ("2026-09-25", "中秋节", .holiday),
            ("2026-10-01", "国庆节", .holiday),
            ("2026-09-20", "调休上班", .workday),
            ("2026-10-10", "调休上班", .workday)
        ]

        for item in cases {
            let date = ISO8601DateFormatter().date(from: item.date + "T00:00:00+08:00")!
            XCTAssertEqual(
                HolidayProvider.labels(on: date, calendar: shanghai),
                [HolidayLabel(name: item.name, kind: item.kind)],
                item.date
            )
        }
    }
}
