# Calendar Indicators and Activity Rings Design

Date: 2026-09-23

Status: Approved in conversation; ready for implementation planning.

## Goal

Improve information density in two existing areas without changing the app's planning, notification, persistence, or AI behavior:

1. Replace the graphical SwiftUI date picker with an Apple-native calendar that can show colored indicators below each date.
2. Move today's workout section to the top of Health and add real Apple Health activity rings for today and the previous three calendar dates.

## User-visible behavior

### Calendar

The month calendar uses an iOS `UICalendarView` wrapped for SwiftUI. It remains bound to `AppStore.selectedDate`, so the existing holiday details and event list continue to follow the selected day.

Each date can display up to three small dots below its number, in a stable left-to-right order:

1. Blue: Chinese traditional festivals, popular Western festivals, and holidays.
2. Red: one or more courses from currently enabled timetables.
3. Yellow: one or more user-created events.

Each category appears at most once per date. Multiple courses therefore still create one red dot. A date containing all three categories shows three dots. Make-up workdays do not create a blue dot, although their existing text labels remain visible after selecting the date.

The dots are informational rather than separate controls. Tapping the date selects it and displays the existing details below the calendar. Selected cells give the dots a light outline so the blue holiday dot remains visible against the system selection color.

### Health layout

The sections appear in this order:

1. Today's workout records
2. Water reminders
3. Sleep reminders
4. Health consultation chat

The first section begins with one compact activity summary card:

- Left: a large three-ring display for the current calendar date, followed by the exact date and the three numeric values.
- Right: three vertically stacked rows for the three preceding calendar dates. Each row contains a small three-ring display, an exact numeric date, and a workout summary.
- Below: today's existing workout rows, manual-entry action, and navigation to the 30-day history.

Relative date words such as “yesterday” are not used. Dates use the user's locale. Dates crossing a year boundary include the year to avoid ambiguity.

## Calendar architecture

### Day indicator model

A small core value type represents the visual categories present on a date. It is derived from:

- `HolidayProvider` labels, excluding `.workday` labels;
- `AppSnapshot.activeEvents`, so disabled timetables are automatically excluded;
- `CalendarEvent.source`, separating `.course` from `.custom`.

The pure derivation logic lives in `MrCalenderCore` and accepts an explicit `Calendar`. It returns categories in the fixed blue-red-yellow presentation order and is independently testable.

### UIKit bridge

`DecoratedCalendarView` is a SwiftUI `UIViewRepresentable` around `UICalendarView` and `UICalendarSelectionSingleDate`.

Its coordinator:

- synchronizes UIKit selection to the SwiftUI `Date` binding;
- synchronizes external `selectedDate` changes back to UIKit;
- supplies `UICalendarView.Decoration.customView` instances containing the colored dots;
- reloads decorations when active events or holiday inputs change;
- preserves the system calendar's locale, time zone, month navigation, dynamic type, and accessibility behavior.

The bridge receives already-derived day indicators. It does not read `AppStore` directly, keeping UI coordination separate from domain logic.

## Activity summary architecture

### Domain model

`DailyActivitySummary` is a lightweight, non-persisted value with:

- calendar date;
- active energy and active-energy goal;
- exercise minutes and exercise goal;
- stand hours and stand goal.

Progress helpers clamp invalid negative values to zero and visual progress to `0...1`. Numeric labels preserve actual values above the goal even when the ring is visually full.

### HealthKit service

`HealthKitService.requestAccess()` requests read access for both:

- workouts;
- activity summaries.

The service adds an activity-summary query covering today and the previous three dates, using local date components and the current calendar time zone. The adapter maps `HKActivitySummary` values into `DailyActivitySummary` and does not save the result into `AppSnapshot`.

Workout samples continue to cover the existing 30-day history. Activity-summary and workout queries are independent so one result remains usable when the other query fails.

### Health presentation model

Health presentation logic builds four day rows:

- today;
- previous date 1;
- previous date 2;
- previous date 3.

Today's activity summary drives the large rings. The other three drive the right-hand small rings.

Workout text for the previous three dates combines Apple Health workouts and manual entries. Rings remain Apple Health-only. A summary with several workouts shows the leading workout and total count, for example `跑步 32 分钟等 3 项`. Single records retain their source label. A day with no workout displays `无训练记录`, even if ordinary movement produced activity-ring progress.

## Loading, authorization, and failures

- Initial page appearance reads data that is already authorized but does not repeatedly prompt.
- The existing button requests both workout and activity-summary access, then refreshes both data sets.
- Pull to refresh reruns both queries without forcing another authorization prompt.
- HealthKit does not reveal whether read access was denied. If no summary is returned, the UI shows empty rings and guidance to check Health permissions and Apple Watch synchronization.
- Activity-summary failure does not hide workout records or manual entries.
- Workout-query failure does not hide successfully loaded activity rings.
- Manual entries remain available without HealthKit access and are never written back to Apple Health.
- HealthKit results remain in view state and refresh from the source rather than becoming stale persisted copies.

## Accessibility and visual rules

- Color is not the only description: date decorations expose the labels “holiday”, “course”, and “custom event” through accessibility text.
- Ring values have VoiceOver labels containing current value, goal, unit, and date.
- Dot and ring colors adapt to light and dark appearance while retaining the requested blue, red, and yellow calendar semantics and Apple-like red, green, and blue activity semantics.
- Numeric values remain visible beside the rings.
- The calendar keeps native dynamic type and VoiceOver date navigation through `UICalendarView`.

## Testing

### Core XCTest coverage

Calendar indicator tests cover:

- each individual category;
- all three categories on one date in stable order;
- several courses collapsing to one red indicator;
- disabled timetables producing no course indicator;
- festivals and holidays producing blue while make-up workdays do not;
- explicit calendar and time-zone boundaries.

Activity presentation tests cover:

- today plus exactly the three preceding dates;
- concrete local date formatting and cross-year formatting;
- Apple and manual workout aggregation;
- empty workout days retaining activity summaries;
- negative progress clamping to zero;
- visual progress clamping to one while numeric values can exceed goals;
- partial activity-summary or workout failure state construction.

### Integration verification

The iOS target must compile the UIKit calendar bridge and HealthKit query. Device verification covers first authorization, existing authorization, denied read access, delayed Apple Watch synchronization, missing individual days, all four days present, manual records, dark mode, VoiceOver descriptions, and pull-to-refresh behavior.

## Non-goals

This change does not:

- modify water or sleep scheduling;
- modify system notification planning;
- change health-chat behavior;
- write manual workouts into Apple Health;
- introduce cloud synchronization or a database;
- change the persisted snapshot schema;
- attempt to reproduce Apple's private Fitness app ring rendering exactly;
- add unrelated calendar recurrence features.

## Delivery risks

- `UICalendarView` decoration refreshes must be limited to affected visible dates to avoid unnecessary UI work.
- HealthKit activity summaries may be absent even when workouts exist; the two data streams must remain independent.
- Date-component queries must use the current calendar and time zone to avoid shifting summaries around midnight or during travel.
- The custom activity rings are an app-owned visualization of public HealthKit values, not a reuse of Apple's private Fitness UI.
