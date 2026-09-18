import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() { print("FAIL: \(name)"); exit(1) }
}
func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "+08:00")! }
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
var state = AppSnapshot()
let start = date("2026-09-18T00:00:00"), end = date("2026-09-19T00:00:00")
state.events = [.init(title: "早课", startsAt: date("2026-09-19T07:00:00"), endsAt: date("2026-09-19T09:00:00"))]
let sleep = SchedulePlanner.sleepPlan(forMorning: end, profile: state.profile, events: state.events, calendar: cal)
check(sleep.wakeAt == date("2026-09-19T06:00:00"), "early course advances wake time")
check(sleep.bedAt == date("2026-09-18T22:00:00"), "eight hours spans midnight")
state.events = [.init(title: "日程", startsAt: date("2026-09-18T08:00:00"), endsAt: date("2026-09-18T10:00:00"))]
state.profile.waterEnabled = true
let water = SchedulePlanner.reminders(state, from: start, to: end, calendar: cal).filter { $0.kind == .water }
check(!water.isEmpty, "water reminders exist")
check(!water.contains { $0.date >= date("2026-09-18T08:00:00") && $0.date < date("2026-09-18T10:00:00") }, "water avoids busy period")
state.reminderRecords = [.init(id: water[0].id, status: .done)]
check(!SchedulePlanner.reminders(state, from: start, to: end, calendar: cal).contains { $0.id == water[0].id }, "completion remains suppressed")
state.reminderRecords = [.init(id: water[0].id, status: .snoozed, snoozedUntil: date("2026-09-18T16:15:00"))]
check(SchedulePlanner.reminders(state, from: start, to: end, calendar: cal).first { $0.id == water[0].id }?.date == date("2026-09-18T16:15:00"), "snooze identity and time")
state.profile.waterIntervalMinutes = 0
check(SchedulePlanner.reminders(state, from: start, to: end, calendar: cal).count < 50, "zero interval bounded")
let many = (0..<100).map { PlannedReminder(id: "\($0)", kind: .water, title: "水", detail: "", date: start.addingTimeInterval(Double($0))) }
let queue = SchedulePlanner.notificationQueue(many.reversed() + [many[99]], after: start)
check(queue.count == 60 && queue.first?.id == "0", "notification cap and earliest ordering")
let r = Restaurant(name: "一食堂")
let safe = Dish(restaurantID: r.id, name: "饭", ingredientsVerified: true)
let allergen = Dish(restaurantID: r.id, name: "花生", allergens: ["花生"], ingredientsVerified: true)
let unknown = Dish(restaurantID: r.id, name: "砂锅")
state.profile.allergies = [" 花生 "]
check(FoodSelector.candidates(dishes: [safe, allergen, unknown], profile: state.profile, meals: [], avoidRecent: false) == [safe, unknown], "allergy filter allows unknown ingredients")
check(FoodSelector.candidates(dishes: [safe], profile: state.profile, meals: [.init(dishID: safe.id, dishName: safe.name)], avoidRecent: true).isEmpty, "recent meal filtering")
let roundTrip = try! SnapshotStore.decode(try! SnapshotStore.encode(state))
check(roundTrip == state, "snapshot persistence roundtrip")
state.schemaVersion = 999
do { _ = try SnapshotStore.decode(SnapshotStore.encode(state)); check(false, "unknown schema rejected") }
catch { check(true, "unknown schema rejected") }
check(HolidayProvider.labels(on: date("2026-09-25T12:00:00")).contains { $0.name == "中秋节" }, "Chinese lunar festival")
check(HolidayProvider.labels(on: date("2026-12-25T12:00:00")).contains { $0.name == "圣诞节" }, "Western festival")
check(HolidayProvider.labels(on: date("2026-09-20T12:00:00")).contains { $0.kind == .workday }, "official make-up day")
var profile = HealthProfile(); profile.exerciseKind = .running; profile.exerciseMinutes = 30; profile.exerciseDistanceKM = 3
check(!WorkoutProgress(kind: .walking, minutes: 40, distanceKM: 4).meets(profile), "workout type matching")
check(!WorkoutProgress(kind: .running, minutes: 40, distanceKM: 2).meets(profile), "workout distance target")
check(WorkoutProgress(kind: .running, minutes: 40, distanceKM: 4).meets(profile), "workout completes both targets")
print("PASS: \(checks) core behavioral checks")
do { try runICSChecks(); print("PASS: ICS behavioral checks") }
catch { print("FAIL: ICS behavioral checks: \(error)"); exit(1) }
