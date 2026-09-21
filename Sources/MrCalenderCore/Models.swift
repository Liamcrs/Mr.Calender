import Foundation

public enum EventSource: String, Codable, Sendable { case custom, course }

public struct CalendarEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var startsAt: Date
    public var endsAt: Date
    public var isAllDay: Bool
    public var location: String
    public var notes: String
    public var source: EventSource
    public var importedUID: String?
    public var reminderMinutes: Int?

    public init(id: String = UUID().uuidString, title: String, startsAt: Date, endsAt: Date,
                isAllDay: Bool = false, location: String = "", notes: String = "",
                source: EventSource = .custom, importedUID: String? = nil, reminderMinutes: Int? = 15) {
        self.id = id; self.title = title; self.startsAt = startsAt; self.endsAt = endsAt
        self.isAllDay = isAllDay; self.location = location; self.notes = notes
        self.source = source; self.importedUID = importedUID; self.reminderMinutes = reminderMinutes
    }
}

public enum WorkoutKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case walking, running, cycling, swimming, basketball, badminton, strengthTraining, hiking, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .walking: return "步行"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .basketball: return "篮球"
        case .badminton: return "羽毛球"
        case .strengthTraining: return "力量训练"
        case .hiking: return "徒步"
        case .other: return "其他运动"
        }
    }
}

public struct HealthProfile: Codable, Equatable, Sendable {
    public var sleepHours: Double = 8
    public var wakeMinute: Int = 7 * 60 + 30
    public var preparationMinutes: Int = 60
    public var waterEnabled = true
    public var waterIntervalMinutes = 120
    public var waterAmountML = 200
    // Kept for decoding schema 1 snapshots; exercise is now sourced from HealthKit/manual records.
    public var exerciseEnabled = false
    public var exerciseKind: WorkoutKind = .walking
    public var exerciseMinutes = 30
    public var exerciseDistanceKM: Double = 0
    public var exerciseMinute = 17 * 60
    public var mealEnabled = false
    public var sleepEnabled = true
    public var allergies: [String] = []
    public var avoidedTags: [String] = []
    public var notes = ""
    public var reportText = ""
    public init() {}
}

public struct HealthChatMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var id: UUID
    public var role: Role
    public var content: String
    public var date: Date
    public init(id: UUID = UUID(), role: Role, content: String, date: Date = Date()) {
        self.id = id; self.role = role; self.content = content; self.date = date
    }
}

public struct ManualWorkout: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: WorkoutKind
    public var minutes: Int
    public var distanceKM: Double
    public var date: Date
    public init(id: UUID = UUID(), kind: WorkoutKind, minutes: Int, distanceKM: Double = 0, date: Date = Date()) {
        self.id = id; self.kind = kind; self.minutes = minutes; self.distanceKM = distanceKM; self.date = date
    }
}

public struct Restaurant: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var note: String
    public var category: String
    public init(id: UUID = UUID(), name: String, note: String = "", category: String = "食堂") {
        self.id = id; self.name = name; self.note = note; self.category = category
    }
}

public struct Dish: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var restaurantID: UUID
    public var name: String
    public var tags: [String]
    public var allergens: [String]
    public var ingredientsVerified: Bool
    public var photoPath: String?
    public var price: Double?
    public init(id: UUID = UUID(), restaurantID: UUID, name: String, tags: [String] = [],
                allergens: [String] = [], ingredientsVerified: Bool = false, price: Double? = nil, photoPath: String? = nil) {
        self.id = id; self.restaurantID = restaurantID; self.name = name; self.tags = tags
        self.allergens = allergens; self.ingredientsVerified = ingredientsVerified; self.price = price; self.photoPath = photoPath
    }
}

public struct MealLog: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var dishID: UUID?
    public var dishName: String
    public var restaurantName: String
    public var date: Date
    public var note: String
    public init(dishID: UUID? = nil, dishName: String, restaurantName: String = "", date: Date = Date(), note: String = "") {
        self.dishID = dishID; self.dishName = dishName; self.restaurantName = restaurantName
        self.date = date; self.note = note
    }
}

public enum ReminderKind: String, Codable, Sendable { case event, water, exercise, meal, sleep }
public enum ReminderStatus: String, Codable, Sendable { case done, skipped, snoozed }

public struct ReminderRecord: Codable, Equatable, Sendable {
    public var id: String
    public var status: ReminderStatus
    public var updatedAt: Date
    public var snoozedUntil: Date?
    public init(id: String, status: ReminderStatus, updatedAt: Date = Date(), snoozedUntil: Date? = nil) {
        self.id = id; self.status = status; self.updatedAt = updatedAt; self.snoozedUntil = snoozedUntil
    }
}

public struct PlannedReminder: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: ReminderKind
    public var title: String
    public var detail: String
    public var date: Date
    public init(id: String, kind: ReminderKind, title: String, detail: String, date: Date) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.date = date
    }
}

public struct AppSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 2
    public var events: [CalendarEvent] = []
    public var restaurants: [Restaurant] = []
    public var dishes: [Dish] = []
    public var meals: [MealLog] = []
    public var reminderRecords: [ReminderRecord] = []
    public var profile = HealthProfile()
    public var healthChat: [HealthChatMessage] = []
    public var manualWorkouts: [ManualWorkout] = []
    public var acceptedAdvice: String = ""
    public var agentBaseURL = "https://api.deepseek.com"
    public var agentModel = "deepseek-v4-pro"
    public var avoidRecentMeals = true
    public var onboardingComplete = false
    public init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion, events, restaurants, dishes, meals, reminderRecords, profile, healthChat, manualWorkouts,
             acceptedAdvice, agentBaseURL, agentModel, avoidRecentMeals, onboardingComplete
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawSchemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = rawSchemaVersion == 1 ? 2 : rawSchemaVersion
        events = try c.decodeIfPresent([CalendarEvent].self, forKey: .events) ?? []
        restaurants = try c.decodeIfPresent([Restaurant].self, forKey: .restaurants) ?? []
        dishes = try c.decodeIfPresent([Dish].self, forKey: .dishes) ?? []
        meals = try c.decodeIfPresent([MealLog].self, forKey: .meals) ?? []
        reminderRecords = try c.decodeIfPresent([ReminderRecord].self, forKey: .reminderRecords) ?? []
        profile = try c.decodeIfPresent(HealthProfile.self, forKey: .profile) ?? HealthProfile()
        if rawSchemaVersion == 1 { profile.waterEnabled = true; profile.sleepEnabled = true }
        healthChat = try c.decodeIfPresent([HealthChatMessage].self, forKey: .healthChat) ?? []
        manualWorkouts = try c.decodeIfPresent([ManualWorkout].self, forKey: .manualWorkouts) ?? []
        acceptedAdvice = try c.decodeIfPresent(String.self, forKey: .acceptedAdvice) ?? ""
        agentBaseURL = try c.decodeIfPresent(String.self, forKey: .agentBaseURL) ?? "https://api.deepseek.com"
        agentModel = try c.decodeIfPresent(String.self, forKey: .agentModel) ?? "deepseek-v4-pro"
        avoidRecentMeals = try c.decodeIfPresent(Bool.self, forKey: .avoidRecentMeals) ?? true
        onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
    }
}
