# Calendar Indicators and Activity Rings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add blue/red/yellow date indicators to an Apple-native calendar and show real Apple Health activity rings for today plus the previous three dated days at the top of Health.

**Architecture:** Keep date classification and activity presentation in `MrCalenderCore` as pure, testable values. Use a thin `UICalendarView` bridge for native date decorations, a HealthKit adapter for activity summaries, and focused SwiftUI views for the ring layout. HealthKit results remain transient view state and the persisted snapshot schema does not change.

**Tech Stack:** Swift 5.9, SwiftUI, UIKit `UICalendarView`, HealthKit, Swift Concurrency, Swift Package Manager, XCTest, Xcode 27.

## Global Constraints

- Minimum supported iOS version remains iOS 17.
- Do not add third-party dependencies.
- Calendar dot order is always blue holiday, red course, yellow custom event.
- Festivals and holidays receive blue; make-up workdays do not.
- Disabled timetables do not produce course dots.
- Rings use Apple Health activity summaries only; workout text merges Apple Health and manual records.
- The right column uses concrete dates for the three calendar days before today, never relative words.
- Visual ring progress is clamped to `0...1`; numeric values retain values above the goal.
- HealthKit data remains transient and `AppSnapshot.schemaVersion` remains `3`.
- Manual workouts are not written to Apple Health.
- Water, sleep, notification, AI, and recurrence behavior must not change.

---

## File map

- Create `Sources/MrCalenderCore/CalendarIndicators.swift`: pure day-category derivation.
- Create `Tests/MrCalenderCoreTests/CalendarIndicatorTests.swift`: category, ordering, visibility, holiday, and time-zone coverage.
- Create `App/Views/DecoratedCalendarView.swift`: `UICalendarView` bridge and three-dot decoration view.
- Modify `App/Views/CalendarView.swift`: replace graphical `DatePicker` with the bridge.
- Create `Sources/MrCalenderCore/ActivityPresentation.swift`: activity values, day grouping, progress, date labels, and workout digest.
- Create `Tests/MrCalenderCoreTests/ActivityPresentationTests.swift`: four-day, progress, formatting, and aggregation coverage.
- Modify `App/Services/HealthKitService.swift`: authorize and query activity summaries.
- Modify `Config/Info.plist`: describe activity-summary reads accurately.
- Create `App/Views/ActivitySummaryView.swift`: reusable rings and compact today/previous-three-day card.
- Modify `App/Views/HealthView.swift`: reorder sections, load both HealthKit streams independently, and display the card.
- Modify `MrCalender.xcodeproj/project.pbxproj`: register four new production Swift files.
- Modify `README.md`: document calendar dots and activity rings.

---

### Task 1: Derive calendar indicators in the core

**Files:**
- Create: `Sources/MrCalenderCore/CalendarIndicators.swift`
- Create: `Tests/MrCalenderCoreTests/CalendarIndicatorTests.swift`

**Interfaces:**
- Consumes: `HolidayProvider.labels(on:calendar:)`, `AppSnapshot.activeEvents`, `CalendarEvent.source`.
- Produces: `DayIndicator` and `CalendarIndicators.indicators(on:snapshot:calendar:) -> [DayIndicator]` for the UIKit bridge.

- [ ] **Step 1: Write failing indicator tests**

Create `Tests/MrCalenderCoreTests/CalendarIndicatorTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
swift test --disable-sandbox --filter CalendarIndicatorTests
```

Expected: compilation fails because `DayIndicator` and `CalendarIndicators` do not exist.

- [ ] **Step 3: Implement the minimal core classifier**

Create `Sources/MrCalenderCore/CalendarIndicators.swift`:

```swift
import Foundation

public enum DayIndicator: Int, CaseIterable, Hashable, Sendable {
    case holiday
    case course
    case customEvent
}

public enum CalendarIndicators {
    public static func indicators(
        on date: Date,
        snapshot: AppSnapshot,
        calendar: Calendar = .current
    ) -> [DayIndicator] {
        var values = Set<DayIndicator>()
        if HolidayProvider.labels(on: date, calendar: calendar).contains(where: { $0.kind != .workday }) {
            values.insert(.holiday)
        }
        for event in snapshot.activeEvents where calendar.isDate(event.startsAt, inSameDayAs: date) {
            values.insert(event.source == .course ? .course : .customEvent)
        }
        return DayIndicator.allCases.filter(values.contains)
    }
}
```

- [ ] **Step 4: Verify GREEN and the full core suite**

Run:

```bash
swift test --disable-sandbox --filter CalendarIndicatorTests
swift test --disable-sandbox
```

Expected: five selected tests pass, followed by the complete suite with zero failures.

- [ ] **Step 5: Commit the core classifier**

```bash
git add Sources/MrCalenderCore/CalendarIndicators.swift Tests/MrCalenderCoreTests/CalendarIndicatorTests.swift
git commit -m "feat: derive calendar day indicators"
```

---

### Task 2: Replace the graphical picker with a decorated native calendar

**Files:**
- Create: `App/Views/DecoratedCalendarView.swift`
- Modify: `App/Views/CalendarView.swift`
- Modify: `MrCalender.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CalendarIndicators.indicators(on:snapshot:calendar:) -> [DayIndicator]` from Task 1.
- Produces: `DecoratedCalendarView(selectedDate:snapshot:calendar:)`, preserving the existing selected-date binding.

- [ ] **Step 1: Register the new sources in the Xcode project before compiling the bridge**

Add these exact file/build references using unused project IDs:

```pbxproj
000000000000000000000422 /* MrCalenderCore/CalendarIndicators.swift in Sources */ = {isa = PBXBuildFile; fileRef = 000000000000000000000209 /* MrCalenderCore/CalendarIndicators.swift */; };
000000000000000000000423 /* Views/DecoratedCalendarView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 000000000000000000000121 /* Views/DecoratedCalendarView.swift */; };

000000000000000000000209 /* MrCalenderCore/CalendarIndicators.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MrCalenderCore/CalendarIndicators.swift; sourceTree = "<group>"; };
000000000000000000000121 /* Views/DecoratedCalendarView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/DecoratedCalendarView.swift; sourceTree = "<group>"; };
```

Add file reference `209` to PBX group `031 /* Sources */`, file reference `121` to PBX group `030 /* App */`, and build references `422` and `423` to build phase `500 /* Sources */`. Do not add either file twice.

- [ ] **Step 2: Add the UIKit bridge**

Create `App/Views/DecoratedCalendarView.swift` with these complete responsibilities:

```swift
import SwiftUI
import UIKit

struct DecoratedCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date
    let snapshot: AppSnapshot
    var calendar: Calendar = .current

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.locale = .current
        view.timeZone = calendar.timeZone
        view.delegate = context.coordinator
        view.wantsDateDecorations = true
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.setSelected(calendar.dateComponents([.year, .month, .day], from: selectedDate), animated: false)
        view.selectionBehavior = selection
        context.coordinator.decoratedDates = context.coordinator.eventDates(snapshot)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let oldDates = context.coordinator.decoratedDates
        context.coordinator.parent = self
        let newDates = context.coordinator.eventDates(snapshot)
        context.coordinator.decoratedDates = newDates
        let selected = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        if let selection = view.selectionBehavior as? UICalendarSelectionSingleDate,
           selection.selectedDate != selected {
            selection.setSelected(selected, animated: false)
        }
        let changed = Array(oldDates.union(newDates))
        if !changed.isEmpty { view.reloadDecorations(forDateComponents: changed, animated: true) }
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: DecoratedCalendarView
        var decoratedDates = Set<DateComponents>()

        init(parent: DecoratedCalendarView) { self.parent = parent }

        func eventDates(_ snapshot: AppSnapshot) -> Set<DateComponents> {
            Set(snapshot.events.map {
                parent.calendar.dateComponents([.year, .month, .day], from: $0.startsAt)
            })
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = parent.calendar.date(from: dateComponents) else { return }
            parent.selectedDate = date
        }

        func calendarView(
            _ calendarView: UICalendarView,
            decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            guard let date = parent.calendar.date(from: dateComponents) else { return nil }
            let indicators = CalendarIndicators.indicators(
                on: date,
                snapshot: parent.snapshot,
                calendar: parent.calendar
            )
            guard !indicators.isEmpty else { return nil }
            return .customView {
                DayIndicatorDots(indicators: indicators)
            }
        }
    }
}

private final class DayIndicatorDots: UIStackView {
    init(indicators: [DayIndicator]) {
        super.init(frame: .zero)
        axis = .horizontal
        spacing = 2
        alignment = .center
        distribution = .equalCentering
        isAccessibilityElement = true
        accessibilityLabel = indicators.map(\.accessibilityTitle).joined(separator: "、")
        for indicator in indicators {
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 5))
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = indicator.color
            dot.layer.cornerRadius = 2.5
            dot.layer.borderColor = UIColor.systemBackground.cgColor
            dot.layer.borderWidth = 0.75
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 5),
                dot.heightAnchor.constraint(equalToConstant: 5)
            ])
            addArrangedSubview(dot)
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private extension DayIndicator {
    var color: UIColor {
        switch self {
        case .holiday: return .systemBlue
        case .course: return .systemRed
        case .customEvent: return .systemYellow
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .holiday: return "节日或假期"
        case .course: return "课程"
        case .customEvent: return "自定义事务"
        }
    }
}
```

- [ ] **Step 3: Replace the existing graphical `DatePicker`**

In `App/Views/CalendarView.swift`, replace the graphical picker block with:

```swift
DecoratedCalendarView(
    selectedDate: $store.selectedDate,
    snapshot: store.snapshot,
    calendar: .current
)
.frame(minHeight: 340)
.padding(.horizontal)
```

Keep the existing list, import flow, event editor, and timetable management unchanged.

- [ ] **Step 4: Compile and verify calendar behavior**

Run:

```bash
swift test --disable-sandbox --filter CalendarIndicatorTests
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderCalendarDerivedData CODE_SIGNING_ALLOWED=NO build
```

Expected: tests pass and the unsigned iOS build ends with `BUILD SUCCEEDED`.

Manual simulator/device check:

1. Select dates and confirm the list follows selection.
2. Confirm October 1 shows blue and dates with enabled courses show red.
3. Add a custom event and confirm yellow appears.
4. Hide its timetable and confirm red disappears without relaunch.
5. Check light mode, dark mode, and VoiceOver labels.

- [ ] **Step 5: Commit the native calendar**

```bash
git add App/Views/DecoratedCalendarView.swift App/Views/CalendarView.swift MrCalender.xcodeproj/project.pbxproj
git commit -m "feat: show colored indicators on calendar dates"
```

---

### Task 3: Add activity presentation values and four-day grouping

**Files:**
- Create: `Sources/MrCalenderCore/ActivityPresentation.swift`
- Create: `Tests/MrCalenderCoreTests/ActivityPresentationTests.swift`
- Modify: `MrCalender.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `[WorkoutRecord]`, `Calendar`, `Locale`.
- Produces: `DailyActivitySummary`, `ActivityDay`, and `ActivityPresentation.days(today:summaries:records:calendar:)` for Health UI and HealthKit mapping.

- [ ] **Step 1: Write failing presentation tests**

Create `Tests/MrCalenderCoreTests/ActivityPresentationTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --disable-sandbox --filter ActivityPresentationTests
```

Expected: compilation fails because the new activity presentation types do not exist.

- [ ] **Step 3: Implement the pure activity presentation model**

Create `Sources/MrCalenderCore/ActivityPresentation.swift`:

```swift
import Foundation

public struct DailyActivitySummary: Equatable, Sendable {
    public let date: Date
    public let activeEnergy: Double
    public let activeEnergyGoal: Double
    public let exerciseMinutes: Double
    public let exerciseGoal: Double
    public let standHours: Double
    public let standGoal: Double

    public init(date: Date, activeEnergy: Double, activeEnergyGoal: Double,
                exerciseMinutes: Double, exerciseGoal: Double,
                standHours: Double, standGoal: Double) {
        self.date = date
        self.activeEnergy = activeEnergy
        self.activeEnergyGoal = activeEnergyGoal
        self.exerciseMinutes = exerciseMinutes
        self.exerciseGoal = exerciseGoal
        self.standHours = standHours
        self.standGoal = standGoal
    }

    public var moveProgress: Double { Self.progress(activeEnergy, goal: activeEnergyGoal) }
    public var exerciseProgress: Double { Self.progress(exerciseMinutes, goal: exerciseGoal) }
    public var standProgress: Double { Self.progress(standHours, goal: standGoal) }

    private static func progress(_ value: Double, goal: Double) -> Double {
        guard value.isFinite, goal.isFinite, value > 0, goal > 0 else { return 0 }
        return min(1, value / goal)
    }
}

public struct ActivityDay: Equatable, Sendable {
    public let date: Date
    public let summary: DailyActivitySummary?
    public let records: [WorkoutRecord]

    public var workoutText: String {
        guard let first = records.first else { return "无训练记录" }
        if records.count == 1 {
            return "\(first.title) \(first.minutes) 分钟 · \(first.source.title)"
        }
        return "\(first.title) \(first.minutes) 分钟等 \(records.count) 项"
    }
}

public enum ActivityPresentation {
    public static func days(today: Date, summaries: [DailyActivitySummary],
                            records: [WorkoutRecord], calendar: Calendar) -> [ActivityDay] {
        let start = calendar.startOfDay(for: today)
        return (0..<4).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: start)!
            let summary = summaries.first { calendar.isDate($0.date, inSameDayAs: date) }
            let dayRecords = records.filter { calendar.isDate($0.date, inSameDayAs: date) }
            return ActivityDay(date: date, summary: summary, records: dayRecords)
        }
    }

    public static func dateLabel(_ date: Date, relativeTo today: Date,
                                 calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: today)
            ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Register `ActivityPresentation.swift` in the app target**

Add these exact file/build references:

```pbxproj
000000000000000000000424 /* MrCalenderCore/ActivityPresentation.swift in Sources */ = {isa = PBXBuildFile; fileRef = 000000000000000000000210 /* MrCalenderCore/ActivityPresentation.swift */; };
000000000000000000000210 /* MrCalenderCore/ActivityPresentation.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MrCalenderCore/ActivityPresentation.swift; sourceTree = "<group>"; };
```

Add file reference `210` to PBX group `031 /* Sources */` and build reference `424` to build phase `500 /* Sources */`.

- [ ] **Step 5: Verify GREEN and commit**

```bash
swift test --disable-sandbox --filter ActivityPresentationTests
swift test --disable-sandbox
git add Sources/MrCalenderCore/ActivityPresentation.swift Tests/MrCalenderCoreTests/ActivityPresentationTests.swift MrCalender.xcodeproj/project.pbxproj
git commit -m "feat: add activity summary presentation model"
```

Expected: selected and full suites pass with zero failures.

---

### Task 4: Read Apple Health activity summaries independently of workouts

**Files:**
- Modify: `App/Services/HealthKitService.swift`
- Modify: `Config/Info.plist`

**Interfaces:**
- Consumes: `DailyActivitySummary` from Task 3 and public HealthKit APIs.
- Produces: `HealthKitService.activitySummaries(from:to:calendar:) async throws -> [DailyActivitySummary]`.

- [ ] **Step 1: Expand authorization to activity summaries**

Replace the single workout read set in `requestAccess()` with:

```swift
let readTypes: Set<HKObjectType> = [
    HKObjectType.workoutType(),
    HKObjectType.activitySummaryType()
]
let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
```

Use the same `readTypes` in `requestAuthorization(toShare:read:)`. Keep the existing `HealthAccessResult` behavior.

- [ ] **Step 2: Add the activity summary query and mapping**

Add this method and mapper to `HealthKitService`:

```swift
func activitySummaries(from start: Date, to end: Date, calendar: Calendar) async throws -> [DailyActivitySummary] {
    guard start <= end else { return [] }
    var queryCalendar = Calendar(identifier: .gregorian)
    queryCalendar.timeZone = calendar.timeZone
    let fields: Set<Calendar.Component> = [.era, .year, .month, .day]
    let startComponents = queryCalendar.dateComponents(fields, from: start)
    let endComponents = queryCalendar.dateComponents(fields, from: end)
    let predicate = HKQuery.predicate(
        forActivitySummariesBetweenStart: startComponents,
        end: endComponents
    )
    let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)
    return try await descriptor.result(for: store).compactMap { summary in
        map(summary, calendar: queryCalendar)
    }
}

private func map(_ summary: HKActivitySummary, calendar: Calendar) -> DailyActivitySummary? {
    let components = summary.dateComponents(for: calendar)
    guard let date = calendar.date(from: components) else { return nil }
    return DailyActivitySummary(
        date: date,
        activeEnergy: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
        activeEnergyGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
        exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
        exerciseGoal: (summary.exerciseTimeGoal ?? summary.appleExerciseTimeGoal).doubleValue(for: .minute()),
        standHours: summary.appleStandHours.doubleValue(for: .count()),
        standGoal: (summary.standHoursGoal ?? summary.appleStandHoursGoal).doubleValue(for: .count())
    )
}
```

- [ ] **Step 3: Update the health usage copy**

Change `NSHealthShareUsageDescription` in `Config/Info.plist` to:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Mr. Calender 读取你授权的运动记录和活动摘要，用于展示训练历史以及活动、锻炼和站立圆环。</string>
```

Do not add write types or change the HealthKit entitlement.

- [ ] **Step 4: Compile the HealthKit adapter**

Run:

```bash
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderHealthKitDerivedData CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED` using the installed Xcode 27 HealthKit interface.

- [ ] **Step 5: Commit the adapter**

```bash
git add App/Services/HealthKitService.swift Config/Info.plist
git commit -m "feat: read Apple activity summaries"
```

---

### Task 5: Build the ring card and move workouts to the top of Health

**Files:**
- Create: `App/Views/ActivitySummaryView.swift`
- Modify: `App/Views/HealthView.swift`
- Modify: `MrCalender.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `[ActivityDay]` from Task 3 and `HealthKitService.activitySummaries` from Task 4.
- Produces: `ActivitySummaryCard(days:today:)` and the approved Health section order.

- [ ] **Step 1: Register the new SwiftUI file**

Add these exact file/build references:

```pbxproj
000000000000000000000425 /* Views/ActivitySummaryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 000000000000000000000122 /* Views/ActivitySummaryView.swift */; };
000000000000000000000122 /* Views/ActivitySummaryView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/ActivitySummaryView.swift; sourceTree = "<group>"; };
```

Add file reference `122` to PBX group `030 /* App */` and build reference `425` to build phase `500 /* Sources */`.

- [ ] **Step 2: Implement reusable rings and the compact four-day card**

Create `App/Views/ActivitySummaryView.swift`. The file must define:

```swift
import SwiftUI

struct ActivitySummaryCard: View {
    let days: [ActivityDay]
    let today: Date
    var calendar: Calendar = .current

    private var todayDay: ActivityDay? { days.first }
    private var previousDays: ArraySlice<ActivityDay> { days.dropFirst().prefix(3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 8) {
                    ActivityRings(summary: todayDay?.summary, date: todayDay?.date ?? today, size: 128)
                    Text(label(for: todayDay?.date ?? today))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ActivityValues(summary: todayDay?.summary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    ForEach(Array(previousDays), id: \.date) { day in
                        HStack(spacing: 8) {
                            ActivityRings(summary: day.summary, date: day.date, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(label(for: day.date)).font(.caption.bold())
                                Text(day.workoutText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func label(for date: Date) -> String {
        ActivityPresentation.dateLabel(date, relativeTo: today, calendar: calendar, locale: .current)
    }
}

private struct ActivityValues: View {
    let summary: DailyActivitySummary?

    var body: some View {
        HStack(spacing: 7) {
            value(summary?.activeEnergy ?? 0, unit: "千卡", color: .pink)
            value(summary?.exerciseMinutes ?? 0, unit: "分钟", color: .green)
            value(summary?.standHours ?? 0, unit: "小时", color: .cyan)
        }
    }

    private func value(_ number: Double, unit: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(number.formatted(.number.precision(.fractionLength(0))))
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ActivityRings: View {
    let summary: DailyActivitySummary?
    let date: Date
    let size: CGFloat

    var body: some View {
        ZStack {
            ring(progress: summary?.moveProgress ?? 0, color: .pink, inset: 0)
            ring(progress: summary?.exerciseProgress ?? 0, color: .green, inset: size * 0.18)
            ring(progress: summary?.standProgress ?? 0, color: .cyan, inset: size * 0.36)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func ring(progress: Double, color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: max(4, size * 0.075))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: max(4, size * 0.075), lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }

    private var accessibilityText: String {
        let dateText = date.formatted(.dateTime.year().month().day())
        guard let summary else { return "\(dateText)，没有读取到活动摘要" }
        return "\(dateText)，活动 \(Int(summary.activeEnergy)) 千卡，目标 \(Int(summary.activeEnergyGoal)) 千卡；锻炼 \(Int(summary.exerciseMinutes)) 分钟，目标 \(Int(summary.exerciseGoal)) 分钟；站立 \(Int(summary.standHours)) 小时，目标 \(Int(summary.standGoal)) 小时"
    }
}
```

- [ ] **Step 3: Add activity-summary state and four-day range to `HealthView`**

Add:

```swift
@State private var activitySummaries: [DailyActivitySummary] = []
@State private var activityStatus: String?

private var activityRange: (start: Date, end: Date) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    return (calendar.date(byAdding: .day, value: -3, to: today)!, today)
}

private var activityDays: [ActivityDay] {
    ActivityPresentation.days(
        today: Date(),
        summaries: activitySummaries,
        records: allRecords,
        calendar: .current
    )
}
```

- [ ] **Step 4: Reorder sections and place the summary card first**

Change the `Form` order to:

```swift
Form {
    workoutSection
    waterSection
    sleepSection
    agentSection
}
```

At the start of `workoutSection`, before the read button, add:

```swift
ActivitySummaryCard(days: activityDays, today: Date())

if let activityStatus {
    Text(activityStatus)
        .font(.caption)
        .foregroundStyle(activityStatus.hasPrefix("活动摘要读取失败") ? .red : .secondary)
}
```

Keep today's workout rows, manual-entry button, and history navigation after the card.

- [ ] **Step 5: Load workouts and activity summaries as independent results**

Refactor `refreshHealth(requestAccess:announceEmpty:)` so each query has its own `do/catch` block after optional authorization:

```swift
private func refreshHealth(requestAccess: Bool, announceEmpty: Bool) async {
    isConnectingHealth = true
    defer { isConnectingHealth = false }
    do {
        if requestAccess { _ = try await Self.healthService.requestAccess() }
    } catch {
        let message = "健康权限请求失败：\(error.localizedDescription)"
        healthStatus = message
        activityStatus = message
        if requestAccess { store.banner = message }
        return
    }

    do {
        let workouts = try await Self.healthService.workouts(from: historyRange.start, to: historyRange.end)
        healthRecords = workouts.map(workoutRecord)
        healthStatus = healthRecords.isEmpty && announceEmpty
            ? "近 30 天未读取到运动，请检查健康权限和 Apple Watch 同步。"
            : healthRecords.isEmpty ? nil : "已读取近 30 天 \(healthRecords.count) 条运动。"
    } catch {
        healthStatus = "运动记录读取失败：\(error.localizedDescription)"
    }

    do {
        activitySummaries = try await Self.healthService.activitySummaries(
            from: activityRange.start,
            to: activityRange.end,
            calendar: .current
        )
        activityStatus = activitySummaries.isEmpty
            ? "未读取到活动摘要，请检查健康权限和 Apple Watch 同步。"
            : nil
    } catch {
        activityStatus = "活动摘要读取失败：\(error.localizedDescription)"
    }

    if requestAccess {
        if !healthRecords.isEmpty || !activitySummaries.isEmpty {
            store.banner = "Apple 健康记录已更新"
        } else if healthStatus?.hasPrefix("运动记录读取失败") != true
            && activityStatus?.hasPrefix("活动摘要读取失败") != true {
            store.banner = "未读取到健康数据，请检查权限和 Apple Watch 同步"
        }
    }
}
```

- [ ] **Step 6: Run all automated and build verification**

```bash
swift test --disable-sandbox
sh scripts/check-core.sh
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderActivityUIDerivedData CODE_SIGNING_ALLOWED=NO build
git diff --check
```

Expected: all XCTest cases and portable checks pass, the iOS build succeeds, and `git diff --check` prints nothing.

- [ ] **Step 7: Perform the required device checks**

On the iPhone 15 Pro paired with Apple Watch Series 9:

1. Launch Health and confirm the workout section is first.
2. Grant workouts and activity-summary access.
3. Confirm today uses a large ring and the right column shows three concrete dates.
4. Confirm the right column excludes today.
5. Add a manual workout on one of the previous three dates and confirm the text summary changes while its ring does not.
6. Deny Health read access and confirm empty rings plus guidance remain usable.
7. Pull to refresh after Watch synchronization and confirm values update.
8. Check the compact card at default and largest accessibility text sizes.

- [ ] **Step 8: Commit the Health UI**

```bash
git add App/Views/ActivitySummaryView.swift App/Views/HealthView.swift MrCalender.xcodeproj/project.pbxproj
git commit -m "feat: show Apple activity rings in Health"
```

---

### Task 6: Update project documentation and perform final verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: completed calendar and Health behavior.
- Produces: accurate user-facing documentation and final verification evidence.

- [ ] **Step 1: Update README feature descriptions**

Update the Calendar bullet to mention blue holiday, red course, and yellow custom-event dots. Update the Health bullet to mention Apple activity rings for today and the previous three concrete dates. State that rings require Health authorization and Apple Watch data.

- [ ] **Step 2: Run final verification from a clean package build**

```bash
swift package clean
swift test --disable-sandbox
sh scripts/check-core.sh
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderCalendarHealthFinalDerivedData CODE_SIGNING_ALLOWED=NO build
git diff --check
rg -l --hidden --glob '!.git/**' --glob '!.build/**' --glob '!.superpowers/**' 'sk-[A-Za-z0-9]{20,}' .
git status --short
```

Expected:

- full XCTest suite has zero failures;
- portable core and ICS checks pass;
- unsigned iOS build ends with `BUILD SUCCEEDED`;
- diff check prints nothing;
- secret scan prints no paths;
- status contains only the intended README change before the final commit.

- [ ] **Step 3: Commit documentation**

```bash
git add README.md
git commit -m "docs: describe calendar indicators and activity rings"
```

- [ ] **Step 4: Review the complete feature diff**

```bash
git log --oneline --decorate -6
git diff --stat HEAD~6..HEAD
git status --short
```

Expected: the six planned feature commits are present and the worktree is clean. Do not claim hosted GitHub Actions or live-device checks passed unless they were actually observed.
