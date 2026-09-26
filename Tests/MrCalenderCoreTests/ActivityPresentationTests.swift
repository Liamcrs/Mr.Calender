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

    func testTodayValuesUseMeasuredDataWhenActivitySummaryIsMissing() {
        let measured = DailyActivityMetrics(
            date: date("2026-09-24T00:00:00"),
            activeEnergy: 235,
            exerciseMinutes: 18,
            standHours: 6
        )

        XCTAssertEqual(ActivityPresentation.values(summary: nil, measured: measured), measured)
    }

    func testTodayValuesPreferOfficialSummaryOverMeasuredFallback() {
        let day = date("2026-09-24T00:00:00")
        let measured = DailyActivityMetrics(date: day, activeEnergy: 235, exerciseMinutes: 18, standHours: 6)
        let summary = DailyActivitySummary(
            date: day, activeEnergy: 240, activeEnergyGoal: 600,
            exerciseMinutes: 20, exerciseGoal: 30, standHours: 7, standGoal: 12
        )

        XCTAssertEqual(
            ActivityPresentation.values(summary: summary, measured: measured),
            DailyActivityMetrics(date: day, activeEnergy: 240, exerciseMinutes: 20, standHours: 7)
        )
    }

    func testStandHourCountDeduplicatesSamplesWithinTheSameLocalHour() {
        XCTAssertEqual(
            ActivityPresentation.standHourCount(
                sampleDates: [
                    date("2026-09-24T09:01:00"),
                    date("2026-09-24T09:55:00"),
                    date("2026-09-24T10:05:00")
                ],
                calendar: calendar
            ),
            2
        )
    }

    func testFailedCurrentDayRefreshDropsOnlyStaleTodaySummary() {
        let yesterday = DailyActivitySummary(
            date: date("2026-09-23T00:00:00"), activeEnergy: 200, activeEnergyGoal: 600,
            exerciseMinutes: 10, exerciseGoal: 30, standHours: 6, standGoal: 12
        )
        let today = DailyActivitySummary(
            date: date("2026-09-24T00:00:00"), activeEnergy: 100, activeEnergyGoal: 600,
            exerciseMinutes: 5, exerciseGoal: 30, standHours: 2, standGoal: 12
        )

        XCTAssertEqual(
            ActivityPresentation.historicalSummaries(
                [yesterday, today], excluding: date("2026-09-24T12:00:00"), calendar: calendar
            ),
            [yesterday]
        )
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

    func testLocalizedNumericDateLabelsIncludeYearOnlyAcrossYearBoundary() {
        let today = date("2027-01-03T12:00:00")
        let cases = [
            (locale: "zh_CN", sameYear: "1/2", priorYear: "2026/12/31"),
            (locale: "en_US", sameYear: "1/2", priorYear: "12/31/2026"),
            (locale: "en_GB", sameYear: "02/01", priorYear: "31/12/2026")
        ]

        for item in cases {
            XCTAssertEqual(
                ActivityPresentation.dateLabel(
                    date("2027-01-02T00:00:00"),
                    relativeTo: today,
                    calendar: calendar,
                    locale: Locale(identifier: item.locale)
                ),
                item.sameYear,
                item.locale
            )
            XCTAssertEqual(
                ActivityPresentation.dateLabel(
                    date("2026-12-31T00:00:00"),
                    relativeTo: today,
                    calendar: calendar,
                    locale: Locale(identifier: item.locale)
                ),
                item.priorYear,
                item.locale
            )
        }
    }
}
