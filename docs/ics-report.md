# ICS subsystem report

## Implemented scope

- Added `ICSParser.parse(_:from:to:timeZone:)` and public `ICSImportResult`.
- Parses unfolded UTF-8 content lines and escaped text values.
- Handles floating, UTC, IANA `TZID`, and all-day date values (exclusive `DTEND`).
- Expands bounded `DAILY` and `WEEKLY` rules with `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, and `WKST`; recurrence arithmetic uses the event timezone to preserve wall-clock time over DST.
- Applies `EXDATE`, `RDATE`, `RECURRENCE-ID` overrides, cancelled occurrences, and cancelled series.
- Produces course events with a 15-minute reminder, raw imported UID, and deterministic FNV-1a IDs keyed by UID plus original occurrence.
- Rejects malformed dates/files, missing required master fields, non-positive duration, duplicate/invalid overrides, unknown timezones, unsupported recurrence fields/frequencies, oversized input/output, and recurrence expansion beyond 100,000 iterations.
- Added a synthetic September 2026 timetable sample with no personal information.

## Verification

Behavioral XCTest suite: `Tests/MrCalenderCoreTests/ICSParserTests.swift` (10 test methods).

Requested command:

```text
swift test --disable-sandbox --scratch-path /private/tmp/mrcalendar-ics-build --filter ICSParserTests
```

Result: SwiftPM compiled the core target, then exited 1 because this CommandLineTools installation has no `XCTest` module (`FoodAndStorageTests.swift:1:8: error: no such module 'XCTest'`). This is an SDK/toolchain limitation, not an ICS compile error.

Portable verification command:

```text
swiftc Sources/MrCalenderCore/Models.swift Sources/MrCalenderCore/ICSParser.swift Tests/Portable/ICSChecks.swift /private/tmp/mrcalendar-ics-main.swift -o /private/tmp/mrcalendar-ics-check
/private/tmp/mrcalendar-ics-check
```

Result: exit 0, `Portable ICS checks passed`. The checks exercise weekly recurrence, historical `COUNT`, `EXDATE`, `RDATE`, overrides and cancellations, stable IDs, all-day exclusive ends, folded/escaped Unicode text, DST wall-clock preservation, cancelled UID reporting, unknown timezone rejection, unsupported frequency rejection, invalid date rejection, and malicious recurrence bounds.

`swiftc -typecheck Sources/MrCalenderCore/Models.swift Sources/MrCalenderCore/ICSParser.swift` also exited 0. `git diff --check` reported no whitespace errors for scoped files.

## Intentional limits / concerns

- Only the requested RRULE subset is accepted. Numeric/ordinal `BYDAY`, `BYSETPOS`, monthly/yearly rules, `DURATION`, and RDATE periods fail transactionally rather than being approximated.
- `TZID` must be an identifier known to Foundation. Embedded custom `VTIMEZONE` definitions are not interpreted.
- A recurrence requiring more than 100,000 day steps is rejected. This protects the importer from hostile or impractically broad horizons, but also rejects genuinely enormous historical imports.
- Full XCTest execution still needs an Xcode/toolchain installation that provides XCTest; rerun the requested command there.
