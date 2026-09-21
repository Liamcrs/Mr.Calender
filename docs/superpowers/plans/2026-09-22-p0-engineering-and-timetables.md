# P0 Engineering Baseline and Multiple Timetables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CI and safe multi-timetable management while preserving current app behavior, displaying course classrooms, hiding imported metadata, fixing event deletion, and anchoring notifications to the current date.

**Architecture:** Keep `AppStore` as the SwiftUI state owner in P0, but move timetable ownership and filtering into a small Foundation-only core module. ICS parsing remains independent; import coordination assigns a timetable namespace after a complete parse succeeds. All calendar, scheduling, and notification consumers use one canonical active-event projection.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation, XCTest, Swift Package Manager, Xcode project, GitHub Actions.

## Global Constraints

- Support iOS 17 and later.
- Keep all user data local except health chat messages explicitly sent to DeepSeek.
- Never store an API key in source, configuration committed to Git, tests, or documentation.
- Multiple timetables may be enabled simultaneously.
- A timetable can be enabled, hidden, reimported, or deleted independently.
- Hidden timetable courses must not affect calendar presentation, Today, sleep/water constraints, reminders, or system notifications.
- Course rows show title, time, and classroom; they do not show course code, week, source, or raw ICS description.
- Do not add a third-party ICS library.
- Do not add new recurrence frequencies in P0.
- Use tests before implementation for every new core behavior.
- Preserve unrelated user changes and do not force-push without a separate explicit request.

---

## File Structure

### Create

- `.github/workflows/ci.yml` — package tests and unsigned generic iOS build.
- `Sources/MrCalenderCore/Timetables.swift` — timetable collection operations, active-event projection, event presentation policy, and stable timetable namespacing.
- `Tests/MrCalenderCoreTests/TimetableTests.swift` — migration and timetable behavior tests.

### Modify

- `Sources/MrCalenderCore/Models.swift` — `Timetable`, `CalendarEvent.timetableID`, schema 3 snapshot decoding.
- `Sources/MrCalenderCore/FoodAndStorage.swift` — accept only current schema 3 after migration.
- `Sources/MrCalenderCore/Planning.swift` — consume active events and expose a deterministic seven-day planning window.
- `Tests/MrCalenderCoreTests/FoodAndStorageTests.swift` — update schema migration expectations.
- `Tests/MrCalenderCoreTests/PlanningTests.swift` — hidden timetable and planning-window regressions.
- `App/State/AppStore.swift` — transactional timetable import, stable-ID deletion, current-date reminder refresh.
- `App/Views/CalendarView.swift` — import naming, location rows, timetable management, reimport, safe deletion.
- `App/Views/TodayView.swift` — active events and classroom display.
- `MrCalender.xcodeproj/project.pbxproj` — compile `Timetables.swift` in the iOS target.
- `README.md` — CI badge, multiple timetable behavior, accurate architecture and test commands.

---

### Task 1: Introduce schema 3 timetable ownership and migration

**Files:**
- Create: `Tests/MrCalenderCoreTests/TimetableTests.swift`
- Modify: `Sources/MrCalenderCore/Models.swift`
- Modify: `Sources/MrCalenderCore/FoodAndStorage.swift`
- Modify: `Tests/MrCalenderCoreTests/FoodAndStorageTests.swift`

**Interfaces:**
- Produces: `Timetable.init(id:name:isEnabled:importedAt:)`
- Produces: `CalendarEvent.timetableID: UUID?`
- Produces: `AppSnapshot.timetables: [Timetable]`
- Produces: schema 1/2 to schema 3 migration using `AppSnapshot.legacyTimetableID`
- Consumes: existing `SnapshotStore.encode` and `SnapshotStore.decode`

- [ ] **Step 1: Add failing migration tests**

Create `Tests/MrCalenderCoreTests/TimetableTests.swift` with deterministic dates and fixtures:

```swift
import XCTest
@testable import MrCalenderCore

final class TimetableTests: XCTestCase {
    private let legacyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testSchemaTwoCoursesMigrateIntoOneEnabledTimetable() throws {
        let json = """
        {
          "schemaVersion": 2,
          "events": [{
            "id": "legacy-course",
            "title": "高等数学",
            "startsAt": 1788748800,
            "endsAt": 1788754200,
            "isAllDay": false,
            "location": "A101",
            "notes": "课程代码 MATH101",
            "source": "course",
            "importedUID": "math@example.edu",
            "reminderMinutes": 15
          }]
        }
        """.data(using: .utf8)!

        let snapshot = try SnapshotStore.decode(json)

        XCTAssertEqual(snapshot.schemaVersion, 3)
        XCTAssertEqual(snapshot.timetables.count, 1)
        XCTAssertEqual(snapshot.timetables[0].id, legacyID)
        XCTAssertEqual(snapshot.timetables[0].name, "已导入课表")
        XCTAssertTrue(snapshot.timetables[0].isEnabled)
        XCTAssertEqual(snapshot.events[0].timetableID, legacyID)
    }

    func testSchemaTwoWithoutCoursesDoesNotCreateTimetable() throws {
        let json = """
        {"schemaVersion":2,"events":[],"restaurants":[],"dishes":[],"meals":[]}
        """.data(using: .utf8)!

        let snapshot = try SnapshotStore.decode(json)

        XCTAssertEqual(snapshot.schemaVersion, 3)
        XCTAssertTrue(snapshot.timetables.isEmpty)
    }

    func testSchemaThreeRoundTripDoesNotDuplicateTimetables() throws {
        var snapshot = AppSnapshot()
        let timetable = Timetable(name: "大二上", importedAt: Date(timeIntervalSince1970: 1_700_000_000))
        snapshot.timetables = [timetable]
        snapshot.events = [CalendarEvent(
            title: "计算机网络",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            endsAt: Date(timeIntervalSince1970: 1_800_003_600),
            source: .course,
            importedUID: "network@example.edu",
            timetableID: timetable.id
        )]

        let once = try SnapshotStore.decode(SnapshotStore.encode(snapshot))
        let twice = try SnapshotStore.decode(SnapshotStore.encode(once))

        XCTAssertEqual(once, twice)
        XCTAssertEqual(twice.timetables, [timetable])
    }
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```sh
swift test --disable-sandbox --filter TimetableTests
```

Expected: compilation fails because `Timetable`, `timetables`, `timetableID`, and the new initializer argument do not exist.

- [ ] **Step 3: Add timetable ownership to the models**

In `Sources/MrCalenderCore/Models.swift`, add:

```swift
public struct Timetable: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var importedAt: Date

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, importedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.importedAt = importedAt
    }
}
```

Add `timetableID` to `CalendarEvent` and its initializer:

```swift
public var timetableID: UUID?

public init(
    id: String = UUID().uuidString,
    title: String,
    startsAt: Date,
    endsAt: Date,
    isAllDay: Bool = false,
    location: String = "",
    notes: String = "",
    source: EventSource = .custom,
    importedUID: String? = nil,
    reminderMinutes: Int? = 15,
    timetableID: UUID? = nil
) {
    self.id = id
    self.title = title
    self.startsAt = startsAt
    self.endsAt = endsAt
    self.isAllDay = isAllDay
    self.location = location
    self.notes = notes
    self.source = source
    self.importedUID = importedUID
    self.reminderMinutes = reminderMinutes
    self.timetableID = timetableID
}
```

Update `AppSnapshot`:

```swift
public static let legacyTimetableID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

public var schemaVersion = 3
public var timetables: [Timetable] = []
```

Include `timetables` in `CodingKeys`. In the custom decoder, decode fields first, then migrate only known older schemas:

```swift
let rawSchemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
schemaVersion = rawSchemaVersion <= 2 ? 3 : rawSchemaVersion
timetables = try c.decodeIfPresent([Timetable].self, forKey: .timetables) ?? []

if rawSchemaVersion <= 2 {
    let courseIndexes = events.indices.filter { events[$0].source == .course }
    if !courseIndexes.isEmpty {
        let legacy = Timetable(
            id: Self.legacyTimetableID,
            name: "已导入课表",
            isEnabled: true,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        timetables = [legacy]
        for index in courseIndexes {
            events[index].timetableID = legacy.id
        }
    }
}
```

- [ ] **Step 4: Require schema 3 from SnapshotStore and update old assertions**

In `Sources/MrCalenderCore/FoodAndStorage.swift`:

```swift
guard value.schemaVersion == 3 else {
    throw NSError(
        domain: "MrCalender",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "不支持的数据版本"]
    )
}
```

In `FoodAndStorageTests.testSchemaOneSnapshotMigratesToSchemaTwo`, rename it to `testSchemaOneSnapshotMigratesToCurrentSchema` and assert:

```swift
XCTAssertEqual(decoded.schemaVersion, 3)
```

- [ ] **Step 5: Run migration and full core tests**

Run:

```sh
swift test --disable-sandbox --filter TimetableTests
swift test --disable-sandbox
```

Expected: all timetable tests and all existing tests pass.

- [ ] **Step 6: Commit the schema migration**

```sh
git add Sources/MrCalenderCore/Models.swift Sources/MrCalenderCore/FoodAndStorage.swift Tests/MrCalenderCoreTests/TimetableTests.swift Tests/MrCalenderCoreTests/FoodAndStorageTests.swift
git commit -m "feat: add timetable ownership and schema migration"
```

---

### Task 2: Add deterministic timetable operations and active-event scheduling

**Files:**
- Create: `Sources/MrCalenderCore/Timetables.swift`
- Modify: `Tests/MrCalenderCoreTests/TimetableTests.swift`
- Modify: `Tests/MrCalenderCoreTests/PlanningTests.swift`
- Modify: `Sources/MrCalenderCore/Planning.swift`
- Modify: `MrCalender.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AppSnapshot.timetables`, `CalendarEvent.timetableID`
- Produces: `AppSnapshot.activeEvents: [CalendarEvent]`
- Produces: `AppSnapshot.addTimetable(name:events:importedAt:) throws -> Timetable`
- Produces: `AppSnapshot.replaceTimetable(id:events:importedAt:) throws`
- Produces: `AppSnapshot.removeTimetable(id:)`
- Produces: `AppSnapshot.removeEvent(id:)`
- Produces: `CalendarEvent.presentationNotes: String`
- Produces: `SchedulePlanner.planningWindow(startingAt:calendar:) -> DateInterval`

- [ ] **Step 1: Add failing catalog and presentation tests**

Append to `TimetableTests`:

```swift
func testSameUIDCanExistInTwoTimetablesWithoutIDCollision() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let parsed = CalendarEvent(
        id: "ics-shared",
        title: "大学英语",
        startsAt: start,
        endsAt: start.addingTimeInterval(3_600),
        source: .course,
        importedUID: "shared@example.edu"
    )
    var snapshot = AppSnapshot()

    let first = try snapshot.addTimetable(name: "主修", events: [parsed])
    let second = try snapshot.addTimetable(name: "辅修", events: [parsed])

    XCTAssertEqual(snapshot.timetables.map(\.id), [first.id, second.id])
    XCTAssertEqual(Set(snapshot.events.map(\.id)).count, 2)
    XCTAssertEqual(Set(snapshot.events.compactMap(\.timetableID)), [first.id, second.id])
}

func testReplacingTimetableIsScopedAndKeepsStableNamespacedIDs() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let parsed = CalendarEvent(
        id: "ics-shared",
        title: "原课程",
        startsAt: start,
        endsAt: start.addingTimeInterval(3_600),
        source: .course,
        importedUID: "shared@example.edu"
    )
    var snapshot = AppSnapshot()
    let first = try snapshot.addTimetable(name: "主修", events: [parsed])
    let second = try snapshot.addTimetable(name: "辅修", events: [parsed])
    let firstID = snapshot.events.first { $0.timetableID == first.id }!.id
    var changed = parsed
    changed.title = "更新课程"

    try snapshot.replaceTimetable(id: first.id, events: [changed])

    XCTAssertEqual(snapshot.events.first { $0.timetableID == first.id }?.id, firstID)
    XCTAssertEqual(snapshot.events.first { $0.timetableID == first.id }?.title, "更新课程")
    XCTAssertEqual(snapshot.events.first { $0.timetableID == second.id }?.title, "原课程")
}

func testDisabledAndDeletedTimetablesAreIsolated() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var snapshot = AppSnapshot()
    let custom = CalendarEvent(title: "自定义安排", startsAt: start, endsAt: start.addingTimeInterval(1_800))
    snapshot.events = [custom]
    let first = try snapshot.addTimetable(name: "主修", events: [
        CalendarEvent(id: "first", title: "高数", startsAt: start, endsAt: start.addingTimeInterval(3_600), source: .course)
    ])
    let second = try snapshot.addTimetable(name: "辅修", events: [
        CalendarEvent(id: "second", title: "英语", startsAt: start, endsAt: start.addingTimeInterval(3_600), source: .course)
    ])

    snapshot.setTimetableEnabled(id: first.id, isEnabled: false)
    XCTAssertEqual(Set(snapshot.activeEvents.map(\.title)), ["自定义安排", "英语"])

    snapshot.removeTimetable(id: second.id)
    XCTAssertEqual(snapshot.events.map(\.title), ["自定义安排", "高数"])
    XCTAssertTrue(snapshot.timetables.contains { $0.id == first.id })
    XCTAssertFalse(snapshot.timetables.contains { $0.id == second.id })
}

func testRemovingEventUsesStableIDInsteadOfFilteredOffset() {
    let early = CalendarEvent(id: "early", title: "早", startsAt: Date(timeIntervalSince1970: 100), endsAt: Date(timeIntervalSince1970: 200))
    let unrelated = CalendarEvent(id: "unrelated", title: "其他日期", startsAt: Date(timeIntervalSince1970: 500), endsAt: Date(timeIntervalSince1970: 600))
    let late = CalendarEvent(id: "late", title: "晚", startsAt: Date(timeIntervalSince1970: 300), endsAt: Date(timeIntervalSince1970: 400))
    var snapshot = AppSnapshot()
    snapshot.events = [unrelated, late, early]

    snapshot.removeEvent(id: late.id)

    XCTAssertEqual(Set(snapshot.events.map(\.id)), ["unrelated", "early"])
}

func testImportedDescriptionsAreNotPresentationNotes() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let course = CalendarEvent(title: "课程", startsAt: start, endsAt: start.addingTimeInterval(3_600), notes: "代码 CS101 · 第 1-16 周", source: .course)
    let custom = CalendarEvent(title: "安排", startsAt: start, endsAt: start.addingTimeInterval(3_600), notes: "带电脑")

    XCTAssertEqual(course.presentationNotes, "")
    XCTAssertEqual(custom.presentationNotes, "带电脑")
}
```

- [ ] **Step 2: Add failing planner tests**

Append to `PlanningTests`:

```swift
func testDisabledTimetableDoesNotCreateRemindersOrConstrainWater() throws {
    var state = AppSnapshot()
    state.profile.sleepEnabled = false
    state.profile.waterEnabled = true
    state.profile.waterIntervalMinutes = 60
    let timetable = Timetable(name: "隐藏课表", isEnabled: false)
    state.timetables = [timetable]
    state.events = [CalendarEvent(
        title: "隐藏课程",
        startsAt: date("2026-09-18T08:00:00"),
        endsAt: date("2026-09-18T10:00:00"),
        source: .course,
        timetableID: timetable.id
    )]

    let result = SchedulePlanner.reminders(
        state,
        from: date("2026-09-18T00:00:00"),
        to: date("2026-09-19T00:00:00"),
        calendar: cal
    )

    XCTAssertFalse(result.contains { $0.kind == .event })
    XCTAssertTrue(result.contains { $0.kind == .water && $0.date == date("2026-09-18T08:30:00") })
}

func testPlanningWindowAlwaysUsesSuppliedNow() {
    let now = date("2026-09-18T16:30:00")
    let window = SchedulePlanner.planningWindow(startingAt: now, calendar: cal)

    XCTAssertEqual(window.start, date("2026-09-18T00:00:00"))
    XCTAssertEqual(window.end, date("2026-09-25T00:00:00"))
}
```

- [ ] **Step 3: Run focused tests and verify failures**

```sh
swift test --disable-sandbox --filter TimetableTests
swift test --disable-sandbox --filter PlanningTests
```

Expected: compilation fails because timetable operations, `presentationNotes`, and `planningWindow` do not exist.

- [ ] **Step 4: Implement the timetable domain module**

Create `Sources/MrCalenderCore/Timetables.swift`:

```swift
import Foundation

public enum TimetableError: Error, LocalizedError, Equatable {
    case emptyName
    case timetableNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "课表名称不能为空"
        case .timetableNotFound: return "找不到需要更新的课表"
        }
    }
}

public extension CalendarEvent {
    var presentationNotes: String { source == .custom ? notes : "" }
}

public extension AppSnapshot {
    var activeEvents: [CalendarEvent] {
        let enabled = Set(timetables.filter(\.isEnabled).map(\.id))
        return events.filter { event in
            event.source == .custom || event.timetableID.map(enabled.contains) == true
        }
    }

    func events(for timetableID: UUID) -> [CalendarEvent] {
        events.filter { $0.timetableID == timetableID }
    }

    @discardableResult
    mutating func addTimetable(name: String, events importedEvents: [CalendarEvent], importedAt: Date = Date()) throws -> Timetable {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TimetableError.emptyName }
        let timetable = Timetable(name: normalized, importedAt: importedAt)
        timetables.append(timetable)
        events.append(contentsOf: namespaced(importedEvents, for: timetable.id))
        return timetable
    }

    mutating func replaceTimetable(id: UUID, events importedEvents: [CalendarEvent], importedAt: Date = Date()) throws {
        guard let index = timetables.firstIndex(where: { $0.id == id }) else {
            throw TimetableError.timetableNotFound
        }
        events.removeAll { $0.timetableID == id }
        events.append(contentsOf: namespaced(importedEvents, for: id))
        timetables[index].importedAt = importedAt
    }

    mutating func setTimetableEnabled(id: UUID, isEnabled: Bool) {
        guard let index = timetables.firstIndex(where: { $0.id == id }) else { return }
        timetables[index].isEnabled = isEnabled
    }

    mutating func removeTimetable(id: UUID) {
        timetables.removeAll { $0.id == id }
        events.removeAll { $0.timetableID == id }
    }

    mutating func removeEvent(id: String) {
        events.removeAll { $0.id == id }
    }

    private func namespaced(_ importedEvents: [CalendarEvent], for timetableID: UUID) -> [CalendarEvent] {
        importedEvents.map { event in
            var value = event
            value.id = "timetable-\(timetableID.uuidString)-\(event.id)"
            value.timetableID = timetableID
            return value
        }
    }
}
```

- [ ] **Step 5: Make SchedulePlanner use the canonical active projection**

At the start of `SchedulePlanner.reminders`, compute:

```swift
let activeEvents = state.activeEvents
```

Use `activeEvents` for event reminders, water conflicts, and sleep planning instead of `state.events`. Change `waterReminders` to accept `[CalendarEvent]` explicitly:

```swift
private static func waterReminders(
    _ state: AppSnapshot,
    events: [CalendarEvent],
    from start: Date,
    to end: Date,
    calendar: Calendar
) -> [PlannedReminder]
```

Add:

```swift
public static func planningWindow(startingAt now: Date, calendar: Calendar) -> DateInterval {
    let start = calendar.startOfDay(for: now)
    let end = calendar.date(byAdding: .day, value: 7, to: start)!
    return DateInterval(start: start, end: end)
}
```

- [ ] **Step 6: Add `Timetables.swift` to the Xcode target**

In `MrCalender.xcodeproj/project.pbxproj`, add unused identifiers:

```text
000000000000000000000420 /* MrCalenderCore/Timetables.swift in Sources */
000000000000000000000207 /* MrCalenderCore/Timetables.swift */
```

Add the file reference to the `Sources` group and the build file to the `PBXSourcesBuildPhase` list, following the existing `WorkoutHistory.swift` entries exactly.

- [ ] **Step 7: Run focused and full tests**

```sh
swift test --disable-sandbox --filter TimetableTests
swift test --disable-sandbox --filter PlanningTests
swift test --disable-sandbox
```

Expected: all tests pass, including hidden timetable and duplicate UID behavior.

- [ ] **Step 8: Commit timetable domain behavior**

```sh
git add Sources/MrCalenderCore/Timetables.swift Sources/MrCalenderCore/Planning.swift Tests/MrCalenderCoreTests/TimetableTests.swift Tests/MrCalenderCoreTests/PlanningTests.swift MrCalender.xcodeproj/project.pbxproj
git commit -m "feat: add isolated timetable operations"
```

---

### Task 3: Integrate transactional imports and current-date reminder planning

**Files:**
- Modify: `App/State/AppStore.swift`
- Modify: `Tests/MrCalenderCoreTests/TimetableTests.swift`

**Interfaces:**
- Consumes: `ICSParser.parse`, timetable domain operations, `SchedulePlanner.planningWindow`
- Produces: `AppStore.importICS(_:timetableName:replacing:)`
- Produces: `AppStore.setTimetableEnabled(id:isEnabled:)`
- Produces: `AppStore.deleteTimetable(id:)`
- Produces: `AppStore.deleteEvent(id:)`
- Produces: `AppStore.refreshReminders(now:)`

- [ ] **Step 1: Add an atomic mutation regression test**

Append to `TimetableTests`:

```swift
func testFailedReplacementLeavesSnapshotUnchanged() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var snapshot = AppSnapshot()
    let timetable = try snapshot.addTimetable(name: "主修", events: [
        CalendarEvent(id: "course", title: "课程", startsAt: start, endsAt: start.addingTimeInterval(3_600), source: .course)
    ])
    let before = snapshot

    XCTAssertThrowsError(try snapshot.replaceTimetable(id: UUID(), events: []))
    XCTAssertEqual(snapshot, before)
    XCTAssertEqual(snapshot.events(for: timetable.id).count, 1)
}
```

- [ ] **Step 2: Run the regression test**

```sh
swift test --disable-sandbox --filter TimetableTests/testFailedReplacementLeavesSnapshotUnchanged
```

Expected: pass if Task 2 mutation guards are correct. If it fails, move all validation before the first mutation in `replaceTimetable`.

- [ ] **Step 3: Replace AppStore import coordination**

Replace `importICS(_:)` with:

```swift
func importICS(_ text: String, timetableName: String? = nil, replacing timetableID: UUID? = nil) {
    do {
        let now = Date.now
        let window = SchedulePlanner.planningWindow(startingAt: now, calendar: calendar)
        let importEnd = calendar.date(byAdding: .year, value: 1, to: window.start)!
        let result = try ICSParser.parse(text, from: window.start, to: importEnd, timeZone: calendar.timeZone)
        var updated = snapshot

        if let timetableID {
            try updated.replaceTimetable(id: timetableID, events: result.events, importedAt: now)
        } else {
            guard let timetableName else { throw TimetableError.emptyName }
            try updated.addTimetable(name: timetableName, events: result.events, importedAt: now)
        }

        snapshot = updated
        banner = "已导入 \(result.events.count) 项课程"
    } catch {
        banner = "课表导入失败：\(error.localizedDescription)"
    }
}
```

The parse and catalog work happen on a local snapshot copy; assign to the published snapshot exactly once after success.

- [ ] **Step 4: Add explicit timetable and event mutations**

Add to `AppStore`:

```swift
func setTimetableEnabled(id: UUID, isEnabled: Bool) {
    snapshot.setTimetableEnabled(id: id, isEnabled: isEnabled)
}

func deleteTimetable(id: UUID) {
    snapshot.removeTimetable(id: id)
    banner = "已删除课表及其课程"
}

func deleteEvent(id: String) {
    snapshot.removeEvent(id: id)
}
```

Remove explicit `refreshReminders()` calls immediately following mutations of `snapshot`, because the published property observer already performs the refresh.

- [ ] **Step 5: Anchor reminder refresh to now**

Replace the selected-date implementation with:

```swift
func refreshReminders(now: Date = .now) {
    let window = SchedulePlanner.planningWindow(startingAt: now, calendar: calendar)
    reminders = SchedulePlanner.reminders(
        snapshot,
        from: window.start,
        to: window.end,
        calendar: calendar
    )
    if isReady { scheduleNotifications() }
}
```

`selectedDate` remains published UI state but is not read by this method.

- [ ] **Step 6: Run core tests and compile the iOS app**

```sh
swift test --disable-sandbox
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderP0Task3 CODE_SIGNING_ALLOWED=NO build
```

Expected: all tests pass and `BUILD SUCCEEDED`. If the local sandbox blocks Swift macro plugins, rerun the identical build outside the sandbox and record both results.

- [ ] **Step 7: Commit AppStore integration**

```sh
git add App/State/AppStore.swift Tests/MrCalenderCoreTests/TimetableTests.swift
git commit -m "fix: make timetable imports isolated and transactional"
```

---

### Task 4: Add timetable management and correct course presentation

**Files:**
- Modify: `App/Views/CalendarView.swift`
- Modify: `App/Views/TodayView.swift`

**Interfaces:**
- Consumes: `AppSnapshot.activeEvents`, `events(for:)`, `CalendarEvent.presentationNotes`
- Consumes: AppStore import, visibility, deletion, and stable event deletion methods from Task 3
- Produces: named import flow and `TimetableManagementView`

- [ ] **Step 1: Replace filtered-offset deletion with stable IDs**

In `CalendarView`, derive the displayed list once:

```swift
private var selectedDayEvents: [CalendarEvent] {
    store.snapshot.activeEvents
        .filter { Calendar.current.isDate($0.startsAt, inSameDayAs: store.selectedDate) }
        .sorted { $0.startsAt < $1.startsAt }
}
```

Delete using the selected rows' IDs:

```swift
.onDelete { offsets in
    let ids = offsets.map { selectedDayEvents[$0].id }
    for id in ids { store.deleteEvent(id: id) }
}
```

Remove the `selectedDate` change handler that calls `refreshReminders()`.

- [ ] **Step 2: Render the classroom and custom notes policy**

Use this course/event row content in Calendar:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text(event.title)
    Text(event.startsAt, format: .dateTime.hour().minute())
        .font(.caption)
        .foregroundStyle(.secondary)
    if !event.location.isEmpty {
        Label(event.location, systemImage: "mappin.and.ellipse")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    if !event.presentationNotes.isEmpty {
        Text(event.presentationNotes)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

Do not render `importedUID`, source, or raw course notes elsewhere in these views.

- [ ] **Step 3: Add the named new-import flow**

Add state:

```swift
@State private var showingImportName = false
@State private var showingImporter = false
@State private var pendingTimetableName = ""
```

The import toolbar action first presents an alert:

```swift
.alert("新课表", isPresented: $showingImportName) {
    TextField("课表名称", text: $pendingTimetableName)
    Button("取消", role: .cancel) { pendingTimetableName = "" }
    Button("选择文件") {
        let name = pendingTimetableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            store.banner = "课表名称不能为空"
            return
        }
        pendingTimetableName = name
        showingImporter = true
    }
} message: {
    Text("例如：大二上、辅修课表")
}
```

After reading the security-scoped file, call:

```swift
store.importICS(text, timetableName: pendingTimetableName)
pendingTimetableName = ""
```

- [ ] **Step 4: Add the management screen and reimport flow**

Add `TimetableManagementView` in `CalendarView.swift`. Its list row must include:

```swift
ForEach(store.snapshot.timetables) { timetable in
    VStack(alignment: .leading, spacing: 6) {
        Toggle(
            timetable.name,
            isOn: Binding(
                get: { timetable.isEnabled },
                set: { store.setTimetableEnabled(id: timetable.id, isEnabled: $0) }
            )
        )
        Text("\(store.snapshot.events(for: timetable.id).count) 节课程 · 导入于 \(timetable.importedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button("重新导入") {
            reimportingTimetableID = timetable.id
            showingImporter = true
        }
    }
    .swipeActions {
        Button("删除", role: .destructive) {
            timetablePendingDeletion = timetable
        }
    }
}
```

Use a confirmation dialog before calling `store.deleteTimetable(id:)`. The screen owns a `.fileImporter` for reimport and calls:

```swift
store.importICS(text, replacing: timetableID)
```

Use the same security-scoped file reading and empty-file checks as the new import path.

- [ ] **Step 5: Make Today use active events and show locations**

Change the Today event source to `store.snapshot.activeEvents`. Add the location below the date only when non-empty:

```swift
if !event.location.isEmpty {
    Label(event.location, systemImage: "mappin.and.ellipse")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 6: Verify tests and iOS compilation**

```sh
swift test --disable-sandbox
sh scripts/check-core.sh
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderP0Task4 CODE_SIGNING_ALLOWED=NO build
```

Expected: 0 XCTest failures, portable checks pass, and `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit the SwiftUI behavior**

```sh
git add App/Views/CalendarView.swift App/Views/TodayView.swift
git commit -m "feat: manage multiple imported timetables"
```

---

### Task 5: Add stable CI and truthful README documentation

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `README.md`

**Interfaces:**
- Consumes: existing `Package.swift` and shared `MrCalender` scheme
- Produces: GitHub Actions workflow `CI`
- Produces: README badge for `ci.yml`

- [ ] **Step 1: Add the GitHub Actions workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
  pull_request:

permissions:
  contents: read

jobs:
  test-and-build:
    runs-on: macos-15
    timeout-minutes: 20
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Show toolchain
        run: |
          swift --version
          xcodebuild -version

      - name: Test core package
        run: swift test --disable-sandbox

      - name: Build iOS app without signing
        run: >-
          xcodebuild
          -project MrCalender.xcodeproj
          -scheme MrCalender
          -configuration Debug
          -destination 'generic/platform=iOS'
          -derivedDataPath "$RUNNER_TEMP/MrCalenderDerivedData"
          CODE_SIGNING_ALLOWED=NO
          build
```

`macos-15` is a supported GitHub-hosted runner label. `actions/checkout@v4` is deliberately conservative for compatibility and does not require repository write permission.

- [ ] **Step 2: Add the badge and update README claims**

Immediately after `# Mr. Calender`, add:

```markdown
[![CI](https://github.com/Liamcrs/Mr.Calender/actions/workflows/ci.yml/badge.svg)](https://github.com/Liamcrs/Mr.Calender/actions/workflows/ci.yml)
```

Update the calendar feature to state that multiple named timetables can be enabled, hidden, reimported, and deleted independently. Update the technical structure to include `Timetables.swift`. Keep the Calendar Engine claim limited to the implemented RFC 5545 subset: `DAILY`, `WEEKLY`, interval/count/until, unnumbered weekly `BYDAY`, EXDATE, RDATE, RECURRENCE-ID, and Foundation timezones.

- [ ] **Step 3: Validate workflow structure and local commands**

Run:

```sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); puts "workflow yaml parsed"'
swift test --disable-sandbox
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderP0CI CODE_SIGNING_ALLOWED=NO build
git diff --check
```

Expected: YAML parses, all tests pass, `BUILD SUCCEEDED`, and `git diff --check` prints nothing.

- [ ] **Step 4: Commit CI and README**

```sh
git add .github/workflows/ci.yml README.md
git commit -m "ci: test core and build iOS app"
```

---

### Task 6: Final P0 verification and evidence report

**Files:**
- Modify only if a verification command reveals a concrete P0 regression.

**Interfaces:**
- Consumes: all P0 deliverables
- Produces: reproducible verification evidence for the user

- [ ] **Step 1: Run the complete test suite from a clean build**

```sh
swift package clean
swift test --disable-sandbox
```

Expected: all XCTest cases pass with 0 failures. Record the exact executed test count from the output rather than copying the pre-P0 count of 36.

- [ ] **Step 2: Run portable checks**

```sh
sh scripts/check-core.sh
```

Expected: `PASS: 19 core behavioral checks` and `PASS: ICS behavioral checks`, unless this plan intentionally adds checks and updates the reported count.

- [ ] **Step 3: Run an unsigned iOS build**

```sh
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderP0Final CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`. If sandbox macro execution fails, rerun the same command outside the sandbox and report both outcomes accurately.

- [ ] **Step 4: Inspect repository integrity**

```sh
git diff --check
git status --short --branch
git log --oneline -8
rg -n --hidden -g '!**/.git/**' -g '!**/.build/**' 'sk-[A-Za-z0-9]{12,}' .
```

Expected: no whitespace errors, no uncommitted implementation files, and no matching API keys. The branch may remain ahead/behind `origin/main` because the earlier amended commit has not been force-pushed; report that fact and do not rewrite or push history without explicit authorization.

- [ ] **Step 5: Deliver the stage report**

Report:

- Modifications grouped by data model, timetable behavior, UI, scheduling, CI, and documentation.
- Why each change was made.
- Exact files created and modified.
- Exact test/build commands and their real exit results.
- Behavior changes: multiple active timetables, classroom display, hidden imported descriptions, current-date notification horizon.
- Risks retained for P1: full-snapshot saves and full notification replacement remain unchanged.

Do not claim that the hosted GitHub Actions run passed until GitHub has actually executed it. Local workflow validation only proves the file parses and the equivalent commands pass locally.
