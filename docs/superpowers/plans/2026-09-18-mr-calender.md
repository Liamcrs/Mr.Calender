# Mr. Calender Implementation Plan

> **For agentic workers:** Use subagent-driven-development for the bounded ICS subsystem and review; root implements the app integration. Tasks below are tracked in `docs/PROGRESS.md`.

**Goal:** 在指定目录交付可由 Xcode 打开的 iPhone 日历与健康生活管理项目。

**Architecture:** Foundation-only core package + SwiftUI iOS application + platform service adapters. Local versioned JSON storage and explicit opt-in cloud analysis.

**Tech Stack:** Swift 5 language mode, iOS 17+, SwiftUI, Foundation, UserNotifications, HealthKit, Vision, PDFKit, Security.

## Global Constraints

- SwiftUI，iOS 17+，Xcode 16+；无第三方运行时依赖。
- 本地数据默认不外传；HealthKit 原始数据不发送。
- 缺少 iOS SDK，不能声称已完成 iOS 编译或真机验证。
- 所有文件在 `/Users/chaoran/Mr.Calender`。

## Task 1: Core models and planning

- [ ] Create `Package.swift`, `Sources/MrCalenderCore/Models.swift`.
- [ ] Add behavioral tests under `Tests/MrCalenderCoreTests/` before planner implementation.
- [ ] Implement `Planning.swift`, `FoodSelection.swift`, `Holidays.swift`, `SnapshotStore.swift`.
- [ ] Run `swift test --disable-sandbox`; cover sleep midnight, busy periods, completion persistence, allergies and interval bounds.

## Task 2: ICS import

**Files:** `Sources/MrCalenderCore/ICSParser.swift`, `Tests/MrCalenderCoreTests/ICSParserTests.swift`, `Samples/timetable.ics`.

**Interface:** `ICSParser.parse(_ text: String, from: Date, to: Date, timeZone: TimeZone) throws -> ICSImportResult`; result exposes `events: [CalendarEvent]`, `importedUIDs: Set<String>`, `warnings: [String]`. Read the actual CalendarEvent model for its initializer. Event `id` must be deterministic by UID/original occurrence. `importedUID` stores raw UID. Courses use 15-minute reminders.

- [ ] Write and run failing tests for unfolded UTF-8 text, time zones, weekly BYDAY/COUNT, UNTIL, EXDATE/RDATE, recurrence overrides/cancellation, stable IDs and unsupported rules.
- [ ] Implement bounded daily/weekly expansion with a hard work limit and explicit validation errors. Unknown TZIDs and unsupported recurrence components must not silently approximate. Preserve wall clock through DST; COUNT applies before range filtering and exclusions. All-day DTEND is exclusive.
- [ ] Generate import warnings for intentionally bounded expansion, return importedUIDs even for cancelled series so merge can remove them. Reject files with no events; parser imports source as `.course`.
- [ ] Add synthetic `Samples/timetable.ics` with recurring courses; no real personal data.
- [ ] Run `swift test --disable-sandbox --filter ICSParserTests`, self-review and document exact output in `docs/ics-report.md`.

## Task 3: Native app and services

- [ ] Create `App/MrCalenderApp.swift`, `App/State/AppStore.swift`, `App/Design/Theme.swift`, and five feature view files.
- [ ] Create notification bridge with persistent actions and rolling cap of 60; HealthKit matched-workout reader; report text extractor; Keychain and HTTPS-only AI client.
- [ ] Create `MrCalender.xcodeproj/project.pbxproj`, shared scheme, `Config/Info.plist`, entitlements and privacy manifest.
- [ ] Implement file importer, editable report preview, consent, validated AI preview and apply, restaurants/dishes/meal editing, calendar create/delete and import preview.
- [ ] Validate Swift syntax with `swiftc -frontend -parse`; verify plist and project syntax with `plutil -lint`.

## Task 4: Review and handoff

- [ ] Read integration code for notification identity/cancellation, health data scope, persistence failures and UI completion behavior.
- [ ] Run core suite, parse app, validate project, record actual outcomes in `docs/VERIFICATION.md`.
- [ ] Write `README.md` with opening, signing, simulator and real-device steps; feature matrix, extension points and known limits.
