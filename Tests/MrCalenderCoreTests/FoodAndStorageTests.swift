import XCTest
@testable import MrCalenderCore

final class FoodAndStorageTests: XCTestCase {
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
    func testRecentMealsCanBeExcludedWithoutRelaxingRestrictions() {
        let dish = Dish(restaurantID: UUID(), name: "米饭", ingredientsVerified: true)
        let meals = [MealLog(dishID: dish.id, dishName: dish.name)]
        XCTAssertTrue(FoodSelector.candidates(dishes: [dish], profile: HealthProfile(), meals: meals, avoidRecent: true).isEmpty)
        XCTAssertEqual(FoodSelector.candidates(dishes: [dish], profile: HealthProfile(), meals: meals, avoidRecent: false).count, 1)
    }

    func testDishCanRoundTripOptionalPhotoAndUnknownIngredients() throws {
        let restaurant = Restaurant(name: "一食堂")
        let dish = Dish(restaurantID: restaurant.id, name: "新菜", photoPath: nil)
        var state = AppSnapshot(); state.restaurants = [restaurant]; state.dishes = [dish]
        let decoded = try SnapshotStore.decode(SnapshotStore.encode(state))
        XCTAssertEqual(decoded.dishes.first?.photoPath, nil)
        XCTAssertEqual(FoodSelector.candidates(dishes: [dish], profile: HealthProfile(), meals: [], avoidRecent: false).count, 1)
    }

    func testSchemaOneSnapshotMigratesToSchemaTwo() throws {
        var state = AppSnapshot(); state.schemaVersion = 1
        let decoded = try SnapshotStore.decode(SnapshotStore.encode(state))
        XCTAssertEqual(decoded.schemaVersion, 2)
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
