# Banner and Food Wheel Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-dismiss banners after five seconds and implement restaurant deletion, same-day dish deduplication, photo preview, and two-action wheel results.

**Architecture:** Keep deterministic food rules and cascade mutation in `MrCalenderCore`, let `AppStore` own timers and photo-file cleanup, and keep presentation state in `FoodView`. Persist reroll skips in the existing snapshot using an optional decoded field for backward compatibility.

**Tech Stack:** Swift 5, SwiftUI, Foundation, PhotosUI, XCTest, iOS 17+

## Global Constraints

- Preserve existing local restaurants, dishes, meals, photos, and settings when decoding older snapshots.
- A banner remains visible for five seconds after the most recent assignment.
- Same-day comparison uses the device's current `Calendar` and time zone.
- Restaurant deletion preserves historical meal logs.
- No third-party dependencies.

---

### Task 1: Same-day food selection and restaurant cascade tests

**Files:**
- Modify: `Tests/MrCalenderCoreTests/FoodAndStorageTests.swift`
- Modify: `Sources/MrCalenderCore/Models.swift`
- Modify: `Sources/MrCalenderCore/FoodAndStorage.swift`

**Interfaces:**
- Produces: `DishSkipRecord`, `AppSnapshot.dishSkips`, `AppSnapshot.removeRestaurant(id:) -> [String]`.
- Produces: `FoodSelector.candidates(dishes:profile:meals:skips:avoidSameDayRepeat:now:calendar:)`.

- [ ] **Step 1: Add failing tests** proving a meal and a reroll skip exclude a dish only on the same calendar day.
- [ ] **Step 2: Add a failing test** proving restaurant removal deletes its dishes, returns their photo paths, and preserves other restaurants plus meal history.
- [ ] **Step 3: Run** `swift test --disable-sandbox --filter FoodAndStorageTests` and confirm failures are caused by the missing skip/cascade APIs.
- [ ] **Step 4: Add `DishSkipRecord` and optional snapshot decoding**, retaining `schemaVersion == 2` and defaulting old snapshots to an empty skip array.
- [ ] **Step 5: Implement same-day candidate filtering and cascade removal** with deterministic `Calendar.isDate(_:inSameDayAs:)` checks.
- [ ] **Step 6: Re-run the focused tests** and confirm they pass.

### Task 2: Five-second banner lifecycle and photo cleanup

**Files:**
- Modify: `App/State/AppStore.swift`
- Modify: `App/Views/RootView.swift`

**Interfaces:**
- Consumes: all existing `store.banner = ...` assignments and `AppSnapshot.removeRestaurant(id:)`.
- Produces: `AppStore.deleteRestaurant(id:)` and automatic banner dismissal.

- [ ] **Step 1: Give `banner` a cancellable dismissal task** that restarts for every non-nil assignment and clears on the main actor after five seconds.
- [ ] **Step 2: Animate banner insertion/removal in `RootView`** without adding a second timer.
- [ ] **Step 3: Add `deleteRestaurant(id:)`** to call the core cascade operation and remove returned photo paths from `DishPhotos`.
- [ ] **Step 4: Parse the changed files** with `xcrun swiftc -frontend -parse`.

### Task 3: Food wheel interaction and photo preview

**Files:**
- Modify: `App/Views/FoodView.swift`
- Modify: `App/Views/SettingsView.swift`
- Modify: `Tests/Portable/main.swift`

**Interfaces:**
- Consumes: `dishSkips`, same-day selector, `AppStore.photoURL(for:)`, and `AppStore.deleteRestaurant(id:)`.
- Produces: result confirmation/reroll actions, leading-edge restaurant swipe deletion, thumbnail/full-screen preview, and same-day Settings copy.

- [ ] **Step 1: Replace the old result button** with “就吃这个！” and “再转一次”; confirmation writes `MealLog`, reroll writes `DishSkipRecord` before spinning.
- [ ] **Step 2: Pass meals and skips into the same-day selector** and update empty-result copy to mention today's exclusions.
- [ ] **Step 3: Add leading-edge destructive swipe actions** for restaurant rows and clear a selected result when its restaurant is deleted.
- [ ] **Step 4: Render saved dish thumbnails** and present a full-screen local photo preview from both list and result card.
- [ ] **Step 5: Change Settings copy** from “近两天” to “一天内不重复” and update portable selector checks.
- [ ] **Step 6: Parse the changed views** and confirm there are no syntax errors.

### Task 4: Full verification and delivery

**Files:**
- Verify all changed files.

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: a tested iPhoneOS build and synchronized GitHub main branch.

- [ ] **Step 1: Run** `swift test --disable-sandbox` and confirm zero failures.
- [ ] **Step 2: Run** `sh scripts/check-core.sh` and confirm portable checks pass.
- [ ] **Step 3: Run** `git diff --check`, plist validation, and secret scanning.
- [ ] **Step 4: Build** `MrCalender` for `generic/platform=iOS` with signing disabled and confirm exit code 0.
- [ ] **Step 5: Commit with the repository's anonymous GitHub email** and push the verified commit to `origin/main`.

