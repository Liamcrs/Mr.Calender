# ICS subsystem implementation brief

Implement the ICS importer for an iOS personal calendar; root is building the app concurrently. Work only in `Sources/MrCalenderCore/ICSParser.swift`, `Tests/MrCalenderCoreTests/ICSParserTests.swift`, `Samples/timetable.ics` and `docs/ics-report.md`. Read `Sources/MrCalenderCore/Models.swift` for existing contracts. Do not edit shared models or other files.

Public API: `public enum ICSParser { public static func parse(_ text: String, from: Date, to: Date, timeZone: TimeZone = .current) throws -> ICSImportResult }`.
`ICSImportResult` exposes public `events: [CalendarEvent]`, `importedUIDs: Set<String>`, `warnings: [String]`.

Courses use `.course`, `importedUID` raw UID and reminderMinutes 15. IDs deterministic by UID + original occurrence so overrides preserve identity. Import caller replaces all matching UID series on reimport.

Support folded UTF-8 text, escaped values, DTSTART/DTEND and all-day exclusive DTEND, TZID and UTC/floating times, DAILY/WEEKLY RRULE with INTERVAL/COUNT/UNTIL/BYDAY/WKST, EXDATE, RDATE, RECURRENCE-ID override and cancellation, cancelled whole series. Reject unknown timezone and unsupported RRULE fields/frequencies explicitly. Bound iteration and output size to avoid hangs. COUNT applies before filtering/exclusions. Preserve local wallclock through DST. Return importedUIDs even when cancelled, and warnings about supplied bounded import horizon. Reject malformed files, invalid date/time (not normalized), missing UID/start or negative duration; don't silently import unsupported recurring entries once. A clearly unsupported feature should fail transactionally, not produce misleading calendar.

Write behavioral tests first, run the focused suite to observe missing implementation then implement and pass. Test normal weekly school schedule, folded text, timezone, COUNT with historical start, EXDATE, RDATE, override and cancellation, stable IDs, unknown RRULE/TZID, malicious work bounds. Supply synthetic 2026 September sample timetable, no private info.

Run `swift test --disable-sandbox --filter ICSParserTests` (initial empty test folder may need first test file). Use a separate `--scratch-path /private/tmp/mrcalendar-ics-build` if root's test build overlaps. Missing SDK/testing libraries are environment limits; report accurately. Root currently has macOS Swift tools but no full Xcode/iOS SDK.

No dependencies. Swift 5.9 tools manifest / Swift 5 language. iOS 17+, macOS 13+ core. Use apply_patch for edits. No secrets. Do not commit (root serializes repository commits). Write detailed results and concerns to `docs/ics-report.md`, return a concise status plus test count and file paths.
