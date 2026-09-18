import XCTest
@testable import MrCalenderCore

final class PlanningTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value + "+08:00")! }

    func testSleepUsesTomorrowEventAndIgnoresAllDay() {
        let tomorrow = date("2026-09-19T00:00:00")
        let events = [CalendarEvent(title: "早课", startsAt: date("2026-09-19T07:00:00"), endsAt: date("2026-09-19T09:00:00")),
                      CalendarEvent(title: "纪念日", startsAt: tomorrow, endsAt: date("2026-09-20T00:00:00"), isAllDay: true)]
        let plan = SchedulePlanner.sleepPlan(forMorning: tomorrow, profile: HealthProfile(), events: events, calendar: cal)
        XCTAssertEqual(plan.wakeAt, date("2026-09-19T06:00:00"))
        XCTAssertEqual(plan.bedAt, date("2026-09-18T22:00:00"))
    }
    func testWaterAvoidsClassAndHonorsCompletedRecord() {
        var state = AppSnapshot(); state.profile.waterEnabled = true
        state.events = [CalendarEvent(title: "课程", startsAt: date("2026-09-18T08:00:00"), endsAt: date("2026-09-18T10:00:00"))]
        let start = date("2026-09-18T00:00:00"), end = date("2026-09-19T00:00:00")
        let water = SchedulePlanner.reminders(state, from: start, to: end, calendar: cal).filter { $0.kind == .water }
        XCTAssertFalse(water.isEmpty)
        XCTAssertFalse(water.contains { $0.date >= date("2026-09-18T08:00:00") && $0.date < date("2026-09-18T10:00:00") })
        state.reminderRecords = [.init(id: water[0].id, status: .done)]
        XCTAssertFalse(SchedulePlanner.reminders(state, from: start, to: end, calendar: cal).contains { $0.id == water[0].id })
    }
    func testSnoozePreservesIdentityAndMovesTime() {
        var state = AppSnapshot()
        state.events = [.init(id: "event", title: "上课", startsAt: date("2026-09-18T10:00:00"), endsAt: date("2026-09-18T11:00:00"))]
        let start = date("2026-09-18T00:00:00"), end = date("2026-09-19T00:00:00")
        let original = SchedulePlanner.reminders(state, from: start, to: end, calendar: cal)[0]
        XCTAssertEqual(original.date, date("2026-09-18T09:45:00"))
        let moved = date("2026-09-18T09:55:00")
        state.reminderRecords = [.init(id: original.id, status: .snoozed, snoozedUntil: moved)]
        XCTAssertEqual(SchedulePlanner.reminders(state, from: start, to: end, calendar: cal)[0].date, moved)
    }
    func testNotificationBudgetKeepsUniqueEarliest60() {
        let base = date("2026-09-18T00:00:00")
        let input = (0..<80).reversed().map { PlannedReminder(id: "\($0)", kind: .water, title: "水", detail: "", date: base.addingTimeInterval(Double($0))) }
        let result = SchedulePlanner.notificationQueue(input + [input[0]], after: base)
        XCTAssertEqual(result.count, 60)
        XCTAssertEqual(result.first?.id, "0")
        XCTAssertEqual(Set(result.map(\.id)).count, 60)
    }
    func testInvalidWaterIntervalCannotLoopForever() {
        var state = AppSnapshot(); state.profile.waterEnabled = true; state.profile.waterIntervalMinutes = 0
        let result = SchedulePlanner.reminders(state, from: date("2026-09-18T00:00:00"), to: date("2026-09-19T00:00:00"), calendar: cal)
        XCTAssertLessThan(result.count, 50)
    }
    func testWorkoutRequiresMatchingTypeAndAllTargets() {
        var profile = HealthProfile(); profile.exerciseKind = .running; profile.exerciseMinutes = 30; profile.exerciseDistanceKM = 3
        XCTAssertFalse(WorkoutProgress(kind: .walking, minutes: 40, distanceKM: 4).meets(profile))
        XCTAssertFalse(WorkoutProgress(kind: .running, minutes: 35, distanceKM: 2).meets(profile))
        XCTAssertTrue(WorkoutProgress(kind: .running, minutes: 35, distanceKM: 4).meets(profile))
    }
}
