# Health and Food Interaction Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore workout reading and entry, add a persistent workout history interface, and make food entry fully interactive.

**Architecture:** Put deterministic workout merging and form validation in `MrCalenderCore`, keep HealthKit as an iOS adapter, and split health UI into overview, history, and add-record views. Remove the form-wide tap recognizer and use SwiftUI keyboard dismissal APIs that do not consume control taps.

**Tech Stack:** Swift 5, SwiftUI, HealthKit, PhotosUI, XCTest, iOS 17+

## Global Constraints

- Target iOS 17.0 or newer and the existing iPhone-first SwiftUI app.
- Store manual workout and food data locally through the existing `AppSnapshot`/`AppStore` path.
- Do not persist copied Apple Health samples.
- Do not add third-party dependencies.
- Keep all user-facing text in Chinese.

---

### Task 1: Test and implement workout history normalization

**Files:**
- Create: `Sources/MrCalenderCore/WorkoutHistory.swift`
- Create: `Tests/MrCalenderCoreTests/WorkoutHistoryTests.swift`

**Interfaces:**
- Produces: `WorkoutRecordSource`, `WorkoutRecord`, and `WorkoutHistory.records(manual:health:from:to:)`.
- Consumes: existing `ManualWorkout` and `WorkoutKind` models.

- [ ] **Step 1: Write failing tests** for inclusive start/exclusive end filtering, newest-first ordering, and duplicate ID removal.
- [ ] **Step 2: Run** `swift test --disable-sandbox --filter WorkoutHistoryTests` and confirm failures are caused by missing workout history types.
- [ ] **Step 3: Implement the minimal normalized record types and pure merge/filter function.** Manual rows use `manual-<UUID>` IDs; HealthKit rows keep their HealthKit UUID-based IDs.
- [ ] **Step 4: Re-run the focused tests** and confirm they pass.

### Task 2: Test and implement food entry validation

**Files:**
- Modify: `Sources/MrCalenderCore/FoodAndStorage.swift`
- Modify: `Tests/MrCalenderCoreTests/FoodAndStorageTests.swift`

**Interfaces:**
- Produces: `FoodEntryDraft` with trimmed names and `isValid`.
- Consumes: raw restaurant and dish strings from `AddFoodView`.

- [ ] **Step 1: Write failing tests** showing whitespace-only names are invalid and valid names are trimmed.
- [ ] **Step 2: Run** `swift test --disable-sandbox --filter FoodAndStorageTests` and confirm failure because `FoodEntryDraft` does not exist.
- [ ] **Step 3: Implement the smallest value type** that trims both required names and exposes `isValid`.
- [ ] **Step 4: Re-run the focused tests** and confirm they pass.

### Task 3: Repair keyboard dismissal and the food add sheet

**Files:**
- Modify: `App/Design/Theme.swift`
- Modify: `App/Views/FoodView.swift`

**Interfaces:**
- Consumes: `FoodEntryDraft` from Task 2 and `AppStore.addDishPhoto(data:)`.
- Produces: interactive food fields, disabled invalid Save, progress/error state for photos, and a keyboard Done action.

- [ ] **Step 1: Remove the form-wide simultaneous tap recognizer** and replace it with a modifier that applies interactive scroll dismissal and a keyboard toolbar Done button.
- [ ] **Step 2: Apply the safe modifier to the food form**, derive a `FoodEntryDraft`, and disable Save until valid.
- [ ] **Step 3: Keep the sheet open on photo load/write failure** and show an inline message; save the trimmed names only after all writes succeed.
- [ ] **Step 4: Run Swift frontend parsing** for `Theme.swift` and `FoodView.swift` and confirm no syntax errors.

### Task 4: Implement HealthKit range querying and workout screens

**Files:**
- Modify: `App/Services/HealthKitService.swift`
- Modify: `App/Views/HealthView.swift`
- Modify: `MrCalender.xcodeproj/project.pbxproj` only if a new source file is needed.

**Interfaces:**
- Consumes: `WorkoutRecord`, `WorkoutHistory.records`, `ManualWorkout`, and `AppStore.snapshot.manualWorkouts`.
- Produces: `HealthKitService.workouts(from:to:)`, a 30-day merged history, `WorkoutHistoryView`, and `AddWorkoutView`.

- [ ] **Step 1: Change HealthKit querying** to accept a half-open date range and sort samples by newest start date.
- [ ] **Step 2: Map HealthKit activity types** into `WorkoutKind` values and normalize distances/durations into `WorkoutRecord`.
- [ ] **Step 3: Replace inline manual controls** with buttons that present `AddWorkoutView` and navigate to `WorkoutHistoryView`.
- [ ] **Step 4: Persist successful manual entries**, refresh merged rows immediately, and support deleting manual rows from history.
- [ ] **Step 5: Add HealthKit loading, error, and zero-result states** without claiming that read access is known when HealthKit returns no samples.
- [ ] **Step 6: Run Swift frontend parsing** for the changed service and view files.

### Task 5: Full verification

**Files:**
- Verify all modified files.

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: evidence that the full app builds and the regression checks pass.

- [ ] **Step 1: Run** `swift test --disable-sandbox` and confirm all tests pass.
- [ ] **Step 2: Run** `sh scripts/check-core.sh` and confirm portable checks pass.
- [ ] **Step 3: Run** `git diff --check` and confirm no whitespace errors.
- [ ] **Step 4: Build** the `MrCalender` scheme for `generic/platform=iOS` with automatic signing disabled for compilation verification.
- [ ] **Step 5: Inspect** the latest signed device app/profile and confirm `com.apple.developer.healthkit = true`.
- [ ] **Step 6: Review the final diff** for only scoped changes and summarize any remaining real-device-only verification.

