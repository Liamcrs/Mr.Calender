import Foundation

public struct FoodEntryDraft: Equatable, Sendable {
    public let restaurantName: String
    public let dishName: String
    public let category: String

    public var isValid: Bool { !restaurantName.isEmpty && !dishName.isEmpty }

    public init(restaurantName: String, dishName: String, category: String) {
        self.restaurantName = restaurantName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dishName = dishName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
    }
}

public enum FoodSelector {
    public static func candidates(dishes: [Dish], profile: HealthProfile, meals: [MealLog],
                                  skips: [DishSkipRecord], avoidSameDayRepeat: Bool,
                                  now: Date = Date(), calendar: Calendar = .current) -> [Dish] {
        let allergies = Set(profile.allergies.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let tags = Set(profile.avoidedTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let mealIDs = meals
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .compactMap(\.dishID)
        let skippedIDs = skips
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .map(\.dishID)
        let excludedIDs = Set(mealIDs + skippedIDs)
        return dishes.filter { dish in
            guard Set(dish.allergens.map { $0.lowercased() }).isDisjoint(with: allergies) else { return false }
            guard Set(dish.tags.map { $0.lowercased() }).isDisjoint(with: tags) else { return false }
            return !avoidSameDayRepeat || !excludedIDs.contains(dish.id)
        }
    }

    public static func candidates(dishes: [Dish], profile: HealthProfile, meals: [MealLog],
                                  avoidRecent: Bool, now: Date = Date(),
                                  calendar: Calendar = .current) -> [Dish] {
        candidates(
            dishes: dishes,
            profile: profile,
            meals: meals,
            skips: [],
            avoidSameDayRepeat: avoidRecent,
            now: now,
            calendar: calendar
        )
    }
}

public extension AppSnapshot {
    mutating func removeRestaurant(id: UUID) -> [String] {
        let removedDishes = dishes.filter { $0.restaurantID == id }
        let photoPaths = removedDishes.compactMap(\.photoPath)
        restaurants.removeAll { $0.id == id }
        dishes.removeAll { $0.restaurantID == id }
        dishSkips.removeAll { skip in removedDishes.contains { $0.id == skip.dishID } }
        return photoPaths
    }
}

public enum SnapshotStore {
    /// The writer must atomically replace persistent data or throw without changing it.
    /// Publish is called exactly once, and only after encoding and writing succeed.
    public static func commit(_ snapshot: AppSnapshot, write: (Data) throws -> Void,
                              publish: (AppSnapshot) -> Void) throws {
        try write(encode(snapshot))
        publish(snapshot)
    }

    public static func encode(_ snapshot: AppSnapshot) throws -> Data { try JSONEncoder().encode(snapshot) }
    public static func decode(_ data: Data) throws -> AppSnapshot {
        let value = try JSONDecoder().decode(AppSnapshot.self, from: data)
        guard value.schemaVersion == 3 else {
            throw NSError(
                domain: "MrCalender",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "不支持的数据版本"]
            )
        }
        return value
    }
}
