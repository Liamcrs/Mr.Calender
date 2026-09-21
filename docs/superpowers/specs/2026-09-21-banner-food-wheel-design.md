# Banner and Food Wheel Improvements Design

## Goal

Make every in-app banner disappear five seconds after its latest assignment, and turn the food wheel into a complete decision flow with restaurant deletion, same-day deduplication, photo preview, confirmation, and reroll tracking.

## Confirmed causes

- `AppStore.banner` is a plain published optional string. `RootView` renders it, but no layer ever clears it.
- `FoodSelector` currently excludes meal IDs whose dates are within two calendar-day components of now. It has no representation for a dish that was shown and rejected.
- Restaurant rows have no swipe action or cascade deletion API.
- Dish rows display only a photo symbol, never the saved image, and have no preview presentation.
- A wheel result currently offers only “记录本餐”, so rerolls cannot be distinguished from untouched results.

## Chosen design

The alternatives were: keep reroll exclusions only in view state, persist same-day skips, or build a larger preference/rating system. Persistent same-day skips are selected because they survive navigation and relaunch while expiring naturally on the next calendar day. The user previously authorized the agent to approve routine project decisions.

`AppStore` owns banner lifetime. Every non-nil assignment cancels the previous dismissal task and starts a new five-second task. A newer banner can never be cleared by an older timer, including when the text is identical.

`DishSkipRecord` stores a dish ID and timestamp in `AppSnapshot`. `FoodSelector` excludes dishes from confirmed meals and reroll skips only when their date is on the same calendar day as `now`. The existing persisted boolean is retained internally for backward compatibility, but its UI label and behavior become “一天内不重复”.

Restaurant deletion calls a core snapshot operation that removes the restaurant and all of its dishes while returning their photo paths. `AppStore` then deletes those local photo files. Historical `MealLog` entries remain because they already preserve dish and restaurant names.

The wheel result card shows the restaurant, dish photo when present, and two actions: “就吃这个！” appends a meal log and closes the result; “再转一次” appends a skip record and immediately spins again. If no candidate remains, the card clears and a five-second banner explains why.

Dish thumbnails are tappable. A full-screen, zoom-friendly preview presents the local image and an explicit close button. The same preview is available from the wheel result.

## Error and edge handling

- Deleting a restaurant also clears a currently displayed result if that result belongs to the restaurant.
- Missing or corrupt photo files fall back to a photo placeholder and do not block deletion.
- Old skip records may remain persisted, but selection only considers records from the current calendar day.
- The restaurant swipe action is placed on the leading edge so a right swipe reveals the destructive action as requested.
- When same-day filtering is disabled in Settings, both confirmed meals and reroll skips stop affecting candidates; allergy and avoided-tag rules remain mandatory.

## Verification

- Red-green unit tests cover same-day vs previous-day meals, reroll skips, restaurant cascade deletion, snapshot persistence, and preservation of meal history.
- Existing core and portable test suites must remain green.
- Changed Swift files must parse and the complete iPhoneOS target must build.
- The repository must remain free of embedded API keys and whitespace errors.

