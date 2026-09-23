import XCTest
@testable import MrCalenderCore

final class ActivityPresentationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+08:00")!
    }

    func testProgressClampsButValuesRemainUnchanged() {
        let summary = DailyActivitySummary(
            date: date("2026-09-23T00:00:00"),
            activeEnergy: 720,
            activeEnergyGoal: 600,
            exerciseMinutes: -5,
            exerciseGoal: 30,
            standHours: 6,
            standGoal: 12
        )
        XCTAssertEqual(summary.moveProgress, 1)
        XCTAssertEqual(summary.exerciseProgress, 0)
        XCTAssertEqual(summary.standProgress, 0.5)
        XCTAssertEqual(summary.activeEnergy, 720)
    }

    func testDaysIncludeTodayAndExactlyThreePreviousDates() {
        let today = date("2026-09-23T14:00:00")
        let days = ActivityPresentation.days(
            today: today,
            summaries: [],
            records: [],
            calendar: calendar
        )
        XCTAssertEqual(days.map(\.date), [
            date("2026-09-23T00:00:00"),
            date("2026-09-22T00:00:00"),
            date("2026-09-21T00:00:00"),
            date("2026-09-20T00:00:00")
        ])
    }

    func testPreviousDayDigestMergesAppleAndManualRecords() {
        let today = date("2026-09-23T14:00:00")
        let records = [
            WorkoutRecord(id: "health", kind: .running, minutes: 32, distanceKM: 5,
                          source: .appleHealth, date: date("2026-09-22T18:00:00")),
            WorkoutRecord(id: "manual", kind: .walking, minutes: 20, distanceKM: 1,
                          source: .manual, date: date("2026-09-22T12:00:00"))
        ]
        let days = ActivityPresentation.days(
            today: today,
            summaries: [],
            records: records,
            calendar: calendar
        )
        XCTAssertEqual(days[1].records.map(\.source), [.appleHealth, .manual])
        XCTAssertEqual(days[1].workoutText, "跑步 32 分钟等 2 项")
        XCTAssertEqual(days[2].workoutText, "无训练记录")
    }

    func testActivitySummaryAndWorkoutStreamsRemainIndependent() {
        let today = date("2026-09-23T14:00:00")
        let priorDay = date("2026-09-22T00:00:00")
        let summary = DailyActivitySummary(
            date: priorDay,
            activeEnergy: 480,
            activeEnergyGoal: 600,
            exerciseMinutes: 25,
            exerciseGoal: 30,
            standHours: 10,
            standGoal: 12
        )
        let summaryOnly = ActivityPresentation.days(
            today: today,
            summaries: [summary],
            records: [],
            calendar: calendar
        )
        XCTAssertEqual(summaryOnly[1].summary, summary)
        XCTAssertEqual(summaryOnly[1].workoutText, "无训练记录")

        let recordOnly = ActivityPresentation.days(
            today: today,
            summaries: [],
            records: [WorkoutRecord(
                id: "manual",
                kind: .walking,
                minutes: 20,
                distanceKM: 1,
                source: .manual,
                date: date("2026-09-22T12:00:00")
            )],
            calendar: calendar
        )
        XCTAssertNil(recordOnly[1].summary)
        XCTAssertEqual(recordOnly[1].workoutText, "步行 20 分钟 · 手动")
    }

    func testConcreteDateLabelsIncludeYearOnlyAcrossYearBoundary() {
        let today = date("2027-01-02T12:00:00")
        XCTAssertEqual(
            ActivityPresentation.dateLabel(
                date("2027-01-01T00:00:00"),
                relativeTo: today,
                calendar: calendar,
                locale: Locale(identifier: "zh_CN")
            ),
            "1月1日"
        )
        XCTAssertEqual(
            ActivityPresentation.dateLabel(
                date("2026-12-31T00:00:00"),
                relativeTo: today,
                calendar: calendar,
                locale: Locale(identifier: "zh_CN")
            ),
            "2026年12月31日"
        )
    }
}
