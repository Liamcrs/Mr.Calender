import XCTest
@testable import MrCalenderCore

final class FoodAndStorageTests: XCTestCase {
    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+08:00")!
    }

    func testFoodEntryDraftRejectsWhitespaceOnlyRequiredNames() {
        let draft = FoodEntryDraft(restaurantName: "  \n ", dishName: "  ", category: "食堂")

        XCTAssertFalse(draft.isValid)
    }

    func testFoodEntryDraftTrimsNamesBeforeSaving() {
        let draft = FoodEntryDraft(restaurantName: "  一食堂 ", dishName: " 牛肉面\n", category: "食堂")

        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.restaurantName, "一食堂")
        XCTAssertEqual(draft.dishName, "牛肉面")
    }

    func testAllergyIsHardFilterAndIngredientConfirmationIsNotRequired() {
        let r = Restaurant(name: "一食堂")
        let safe = Dish(restaurantID: r.id, name: "蔬菜饭", ingredientsVerified: true)
        let peanut = Dish(restaurantID: r.id, name: "花生鸡丁", allergens: ["花生"], ingredientsVerified: true)
        let unknown = Dish(restaurantID: r.id, name: "砂锅")
        var p = HealthProfile(); p.allergies = [" 花生 "]
        let result = FoodSelector.candidates(dishes: [safe, peanut, unknown], profile: p, meals: [], avoidRecent: false)
        XCTAssertEqual(Set(result.map(\.id)), Set([safe.id, unknown.id]))
    }
    func testOnlyMealsFromTheSameCalendarDayAreExcluded() {
        let sameDayDish = Dish(restaurantID: UUID(), name: "米饭")
        let yesterdayDish = Dish(restaurantID: UUID(), name: "面条")
        let meals = [
            MealLog(dishID: sameDayDish.id, dishName: sameDayDish.name, date: date("2026-09-21T08:00:00")),
            MealLog(dishID: yesterdayDish.id, dishName: yesterdayDish.name, date: date("2026-09-20T20:00:00"))
        ]

        let result = FoodSelector.candidates(
            dishes: [sameDayDish, yesterdayDish], profile: HealthProfile(), meals: meals, skips: [],
            avoidSameDayRepeat: true, now: date("2026-09-21T12:00:00"), calendar: shanghaiCalendar
        )

        XCTAssertEqual(result.map(\.id), [yesterdayDish.id])
    }

    func testRerollSkipOnlyExcludesDishOnTheSameCalendarDay() {
        let sameDayDish = Dish(restaurantID: UUID(), name: "米饭")
        let yesterdayDish = Dish(restaurantID: UUID(), name: "面条")
        let skips = [
            DishSkipRecord(dishID: sameDayDish.id, date: date("2026-09-21T09:00:00")),
            DishSkipRecord(dishID: yesterdayDish.id, date: date("2026-09-20T23:00:00"))
        ]

        let result = FoodSelector.candidates(
            dishes: [sameDayDish, yesterdayDish], profile: HealthProfile(), meals: [], skips: skips,
            avoidSameDayRepeat: true, now: date("2026-09-21T12:00:00"), calendar: shanghaiCalendar
        )

        XCTAssertEqual(result.map(\.id), [yesterdayDish.id])
    }

    func testDisablingSameDayRepeatKeepsMealsAndSkipsEligible() {
        let dish = Dish(restaurantID: UUID(), name: "米饭")
        let meals = [MealLog(dishID: dish.id, dishName: dish.name)]
        let skips = [DishSkipRecord(dishID: dish.id)]

        let result = FoodSelector.candidates(
            dishes: [dish], profile: HealthProfile(), meals: meals, skips: skips,
            avoidSameDayRepeat: false
        )

        XCTAssertEqual(result.map(\.id), [dish.id])
    }

    func testRemovingRestaurantCascadesDishesAndReturnsPhotosButPreservesMeals() {
        let removedRestaurant = Restaurant(name: "一食堂")
        let keptRestaurant = Restaurant(name: "二食堂")
        let removedDish = Dish(restaurantID: removedRestaurant.id, name: "盖饭", photoPath: "cover.jpg")
        let keptDish = Dish(restaurantID: keptRestaurant.id, name: "面条", photoPath: "keep.jpg")
        let meal = MealLog(dishID: removedDish.id, dishName: removedDish.name, restaurantName: removedRestaurant.name)
        var snapshot = AppSnapshot()
        snapshot.restaurants = [removedRestaurant, keptRestaurant]
        snapshot.dishes = [removedDish, keptDish]
        snapshot.meals = [meal]

        let photoPaths = snapshot.removeRestaurant(id: removedRestaurant.id)

        XCTAssertEqual(photoPaths, ["cover.jpg"])
        XCTAssertEqual(snapshot.restaurants, [keptRestaurant])
        XCTAssertEqual(snapshot.dishes, [keptDish])
        XCTAssertEqual(snapshot.meals, [meal])
    }

    func testDishCanRoundTripOptionalPhotoAndUnknownIngredients() throws {
        let restaurant = Restaurant(name: "一食堂")
        let dish = Dish(restaurantID: restaurant.id, name: "新菜", photoPath: nil)
        var state = AppSnapshot(); state.restaurants = [restaurant]; state.dishes = [dish]
        let decoded = try SnapshotStore.decode(SnapshotStore.encode(state))
        XCTAssertEqual(decoded.dishes.first?.photoPath, nil)
        XCTAssertEqual(FoodSelector.candidates(dishes: [dish], profile: HealthProfile(), meals: [], avoidRecent: false).count, 1)
    }

    func testDishSkipsRoundTripAndOldSnapshotsDefaultToEmpty() throws {
        var state = AppSnapshot()
        let skip = DishSkipRecord(dishID: UUID(), date: date("2026-09-21T09:00:00"))
        state.dishSkips = [skip]
        XCTAssertEqual(try SnapshotStore.decode(SnapshotStore.encode(state)).dishSkips, [skip])

        let oldJSON = """
        {"schemaVersion":2,"events":[],"restaurants":[],"dishes":[],"meals":[]}
        """.data(using: .utf8)!
        XCTAssertTrue(try SnapshotStore.decode(oldJSON).dishSkips.isEmpty)
    }

    func testSchemaOneSnapshotMigratesToCurrentSchema() throws {
        var state = AppSnapshot(); state.schemaVersion = 1
        let decoded = try SnapshotStore.decode(SnapshotStore.encode(state))
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertTrue(decoded.healthChat.isEmpty)
        XCTAssertTrue(decoded.profile.waterEnabled)
        XCTAssertTrue(decoded.profile.sleepEnabled)
    }
    func testSnapshotRoundTripAndRefusesUnknownSchema() throws {
        var state = AppSnapshot(); state.restaurants = [.init(name: "一楼", category: "食堂")]
        let data = try SnapshotStore.encode(state)
        XCTAssertEqual(try SnapshotStore.decode(data), state)
        state.schemaVersion = 999
        XCTAssertThrowsError(try SnapshotStore.decode(SnapshotStore.encode(state)))
    }
    func testChineseAndWesternFestivalsAndWorkday() {
        let fmt = ISO8601DateFormatter()
        let midAutumn = fmt.date(from: "2026-09-25T04:00:00Z")!
        let christmas = fmt.date(from: "2026-12-25T04:00:00Z")!
        let workday = fmt.date(from: "2026-09-20T04:00:00Z")!
        XCTAssertTrue(HolidayProvider.labels(on: midAutumn).contains { $0.name.contains("中秋") })
        XCTAssertTrue(HolidayProvider.labels(on: christmas).contains { $0.name == "圣诞节" })
        XCTAssertTrue(HolidayProvider.labels(on: workday).contains { $0.kind == .workday })
    }
}
