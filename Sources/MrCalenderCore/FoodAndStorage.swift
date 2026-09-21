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
    public static func candidates(dishes: [Dish], profile: HealthProfile, meals: [MealLog], avoidRecent: Bool, now: Date = Date(), calendar: Calendar = .current) -> [Dish] {
        let allergies = Set(profile.allergies.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let tags = Set(profile.avoidedTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let recentIDs: Set<UUID> = Set(meals.filter { calendar.dateComponents([.day], from: $0.date, to: now).day.map { abs($0) <= 2 } ?? false }.compactMap(\.dishID))
        return dishes.filter { dish in
            guard Set(dish.allergens.map { $0.lowercased() }).isDisjoint(with: allergies) else { return false }
            guard Set(dish.tags.map { $0.lowercased() }).isDisjoint(with: tags) else { return false }
            return !avoidRecent || !recentIDs.contains(dish.id)
        }
    }
}

public enum SnapshotStore {
    public static func encode(_ snapshot: AppSnapshot) throws -> Data { try JSONEncoder().encode(snapshot) }
    public static func decode(_ data: Data) throws -> AppSnapshot {
        let value = try JSONDecoder().decode(AppSnapshot.self, from: data)
        guard value.schemaVersion == 2 else { throw NSError(domain: "MrCalender", code: 1, userInfo: [NSLocalizedDescriptionKey: "不支持的数据版本"]) }
        return value
    }
}
