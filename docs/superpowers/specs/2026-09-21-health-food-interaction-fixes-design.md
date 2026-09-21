# Health and Food Interaction Fixes Design

## Context and confirmed causes

Three user-visible failures are in scope:

1. Apple Health workouts appear not to load.
2. Manual workout entry has no clear interaction or persistent history screen.
3. The food add sheet opens, but its fields cannot be used reliably.

The food form regression and the hard-to-use inline workout controls both appeared after commit `2a4a5a2`, which attached a `simultaneousGesture(TapGesture())` to complete `Form` hierarchies. A tap that focuses a text field also asks UIKit to resign the first responder, so input immediately loses focus. The HealthKit capability and provisioning profile both contain `com.apple.developer.healthkit`; the data problem is therefore in app behavior and diagnostics rather than a missing entitlement. The current app queries only the current day and reports “connected” even when the query returns no samples. HealthKit does not reveal denied read access, so an empty query must be explained rather than presented as success.

## Considered approaches

### A. Minimal patch

Remove the global tap gesture, keep the inline manual workout controls, and change the HealthKit status string. This is low risk but leaves the requested record page missing and makes history hard to inspect.

### B. Focused workflow repair (selected)

Replace the unsafe tap gesture with scroll dismissal plus a keyboard “完成” action. Move manual entry into a dedicated sheet, add a workout history page, query the last 30 days from HealthKit, and show explicit empty/error states. Keep food entry as a sheet but add validation, loading state, and safe input behavior. This addresses all three symptoms without changing unrelated app architecture.

### C. Full health data repository

Persist normalized HealthKit samples alongside manual workouts and build background synchronization. This would support offline history but introduces deletion, deduplication, and privacy lifecycle work that is unnecessary for the current personal-use app.

The user previously authorized the agent to approve routine project decisions while they are away, so approach B is selected.

## Architecture

`WorkoutHistory` in the core package owns date-range filtering, stable merging, sorting, and duplicate removal for normalized workout rows. It has no HealthKit dependency and is unit tested.

`HealthKitService` remains the platform adapter. It requests read authorization and fetches workouts for an explicit half-open date range, sorted newest first. `HealthView` owns loading/error state and maps HealthKit workouts into the core representation. HealthKit records are fetched live; manual records remain in `AppSnapshot` and persist through the existing store.

`WorkoutHistoryView` displays the merged 30-day history. `AddWorkoutView` collects type, date/time, duration, and optional distance, then calls a closure with a validated `ManualWorkout`. The health overview shows today’s summary and links to history/add actions.

`AddFoodView` uses trimmed input validation, disables Save until required values are valid, reports photo-loading failure, and avoids any parent tap recognizer that competes with controls.

## Interaction design

- Forms use `.scrollDismissesKeyboard(.interactively)` and a keyboard toolbar “完成” button.
- Tapping “手动补录” always opens a form; a successful save closes it, persists the record, refreshes the list, and shows a banner.
- “全部运动记录” opens a dated, newest-first list covering 30 days. Manual and Apple Health records are visually labeled.
- “读取 Apple 健康” refreshes records. When no samples are returned, the app explains that either no workout exists in the period or Health read access is disabled, and directs the user to Settings > Health > Data Access & Devices.
- Food Save is unavailable for blank restaurant or dish names. Photo selection shows progress and a recoverable inline error.

## Error handling and privacy

- HealthKit unavailable, authorization request errors, and query errors use distinct Chinese messages.
- Empty HealthKit results are not called a successful connection.
- Read authorization is never inferred from an empty query because HealthKit intentionally masks denied read access.
- HealthKit samples are not copied into the local snapshot; only manual records are persisted.
- Food photo write failures leave the form open and show an error instead of silently saving without the selected photo.

## Testing and verification

- Add core unit tests for range filtering, newest-first merge, and deduplication.
- Add core unit tests for trimmed food-entry validation.
- Run all Swift package tests and portable checks.
- Parse all changed Swift source files and perform an iPhoneOS Xcode build.
- Inspect the built app entitlements for the HealthKit capability.
- Manually verify the add-food and manual-workout sheets in Xcode/device when available.

