# P0 Engineering Baseline and Multiple Timetables Design

## Context

Mr. Calender already has a testable Foundation-only core, a SwiftUI application,
local JSON persistence, ICS importing, reminder planning, HealthKit integration,
and system notification scheduling. The current core test suite passes, but the
application has no CI and imported courses are stored in one flat event array
without timetable ownership.

This P0 phase improves correctness and engineering feedback without replacing the
existing architecture. It also implements the confirmed product behavior: multiple
imported timetables may be enabled at the same time, and each timetable can be
shown, hidden, or deleted independently.

## Goals

- Add stable GitHub Actions checks for the Swift package and unsigned iOS build.
- Model imported timetables explicitly and associate each imported course with one
  timetable.
- Allow multiple timetables to coexist, including when their ICS UIDs overlap.
- Allow a timetable to be enabled, hidden, or deleted without affecting custom
  events or other timetables.
- Show course classrooms while hiding imported course code, week, source, and raw
  ICS description metadata.
- Fix event deletion so the row selected by the user is the event that is removed.
- Ensure browsing another calendar date cannot change the system notification
  planning window.
- Add regression tests for all new core behavior and update documentation only
  after the checks exist.

## Non-goals

- No broad AppStore rewrite in P0.
- No Calendar Engine file split in P0.
- No new recurrence frequencies in P0.
- No notification scoring system or complete differential scheduler in P0.
- No LLM tool calling or AI architecture changes in P0.
- No SwiftData migration.

## Data Model

Introduce a `Timetable` value type in `MrCalenderCore`:

```swift
public struct Timetable: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var importedAt: Date
}
```

`CalendarEvent` gains an optional `timetableID: UUID?`:

- Custom events use `nil`.
- Every newly imported course uses the destination timetable ID.
- Existing imported events are assigned to one migrated timetable.

`AppSnapshot` gains `timetables: [Timetable]` and advances from schema version 2
to schema version 3. Schema 1 continues to migrate through the existing schema 2
defaults before the timetable migration is applied.

### Migration behavior

- A schema 1 or 2 snapshot with imported course events creates exactly one enabled
  timetable named `已导入课表` and associates every existing course event with it.
- A schema 1 or 2 snapshot without imported course events creates no timetable.
- Custom events remain unowned.
- Unknown future schema versions remain rejected.
- Migration output is schema version 3 and round-trips without creating additional
  timetables.

## Import Semantics

The import UI requests a non-empty timetable name before presenting the file
picker. One selected ICS file creates one timetable.

The parser remains independent of timetable storage. `ICSParser` continues to
produce course events and imported UIDs; the import coordination layer assigns the
new timetable ID to every parsed event.

Course replacement is scoped to a timetable. Reimporting into an existing
timetable replaces only matching imported UIDs owned by that timetable. Importing
a new timetable never deletes events from another timetable, even when both files
contain the same UID.

The P0 UI creates a new timetable for each import. Reimport support is exposed from
the timetable management screen so the destination timetable is explicit instead
of inferred from its display name.

An import is committed only after the complete ICS text parses successfully. A
failed import leaves the snapshot unchanged and presents a five-second banner.

## Visibility and Deletion

An enabled timetable contributes its events to:

- Calendar day lists
- The Today screen
- Sleep and water planning constraints
- Event reminder generation
- System notification scheduling

A disabled timetable and its events remain persisted but are excluded from all of
those consumers. Custom events are always active.

Deleting a timetable removes the timetable and all events whose `timetableID`
matches it. It does not remove custom events, other timetable events, restaurants,
health data, or reminder history. Reminder regeneration follows the mutation.

Core helpers expose active events and timetable deletion as deterministic,
testable transformations rather than duplicating filters across SwiftUI views.

## Calendar and Today Presentation

Course rows display:

- Course title
- Start time
- Classroom from ICS `LOCATION`, when present

Course rows do not display:

- ICS UID or course code
- Week-number metadata
- Import source labels
- Raw ICS `DESCRIPTION`

Custom events continue to display their user-authored notes. Imported descriptions
may remain in memory for compatibility, but presentation must not render them as
course notes.

Event deletion uses the selected row's stable event ID. It never applies offsets
from a filtered/sorted list directly to the backing snapshot array.

## Timetable Management UI

The Calendar toolbar contains separate actions for importing and managing
timetables. The management screen lists every timetable with:

- Name
- Enabled toggle
- Course count
- Import date
- Reimport action
- Trailing swipe deletion

Deletion requires confirmation because it removes all courses owned by that
timetable. Toggling visibility is immediate and reversible.

## Notification Planning Window

`selectedDate` remains view-only state. Changing it refreshes the displayed day but
does not define the system notification horizon.

App-level reminder refresh uses `Date.now` as its anchor and plans the next seven
days. Calendar rendering derives its event rows separately from the selected date.
This P0 change retains the existing full notification replacement behavior; a
differential notification scheduler is deferred to P1.

## CI

Add one GitHub Actions workflow triggered by pushes and pull requests. It runs on a
macOS runner and performs two independent checks:

1. `swift test --disable-sandbox`
2. An unsigned generic iOS build of `MrCalender.xcodeproj` and the `MrCalender`
   scheme with `CODE_SIGNING_ALLOWED=NO`

The workflow should stay dependency-free and use the Xcode version available on
the selected runner. The README receives a build/test badge linked to this workflow
only after the workflow file and commands are established.

## Testing Strategy

Core tests are written before implementation and cover:

- Schema 2 migration with imported courses
- Schema 2 migration without imported courses
- Schema 3 round-trip stability
- Two timetables containing the same ICS UID
- Replacement scoped to one timetable
- Disabled timetable exclusion from active events and reminders
- Timetable deletion isolation
- Custom event preservation
- Stable-ID deletion from a filtered and sorted day list
- Course location preservation
- Course presentation policy that omits imported descriptions
- Notification planning anchored to the current date rather than selected UI date

Existing ICS, scheduling, food, and workout tests must continue to pass. Final P0
verification runs the complete Swift package suite, the portable core checks,
`git diff --check`, and the unsigned generic iOS build.

## Error Handling

- Reject empty or whitespace-only timetable names in the UI.
- Preserve the entire snapshot when parsing or file access fails.
- Surface import, persistence, and notification failures through the existing
  auto-dismissing banner when an actionable message is available.
- Keep unsupported ICS recurrence rules explicit; do not approximate them.

## Risks and Mitigations

- **Migration data loss:** test schema 1, schema 2, and repeated schema 3 decoding
  with deterministic fixtures.
- **UID collision across timetables:** scope replacement by timetable ID and test
  identical UIDs in two timetables.
- **Hidden courses still influencing sleep or water:** provide one canonical active
  event projection and use it for every planner consumer.
- **Notification behavior change:** only change the horizon anchor in P0; defer
  differential scheduling to P1.
- **Xcode runner drift:** keep CI build flags explicit and avoid pinning features to
  a local signing identity or simulator runtime.

## P1 and P2 Boundaries

P1 will split Calendar Engine responsibilities only where new recurrence behavior
requires it, add valuable RFC 5545 monthly/yearly subsets, formalize scheduling
constraints, extract persistence, and improve notification synchronization.

P2 may add structured LLM tool calling, broader UI automation, screenshots, and
portfolio presentation once the engineering foundation is stable.
