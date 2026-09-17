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
    case walking, running, swimming, basketball
    public var id: String { rawValue }
    public var title: String {
        switch self { case .walking: return "步行"; case .running: return "跑步"
        case .swimming: return "游泳"; case .basketball: return "篮球" }
    }
}

public struct HealthProfile: Codable, Equatable, Sendable {
    public var sleepHours: Double = 8
    public var wakeMinute: Int = 7 * 60 + 30
    public var preparationMinutes: Int = 60
    public var waterEnabled = false
    public var waterIntervalMinutes = 120
    public var waterAmountML = 200
    public var exerciseEnabled = false
    public var exerciseKind: WorkoutKind = .walking
    public var exerciseMinutes = 30
    public var exerciseDistanceKM: Double = 0
    public var exerciseMinute = 17 * 60
    public var mealEnabled = false
    public var sleepEnabled = false
    public var allergies: [String] = []
    public var avoidedTags: [String] = []
    public var notes = ""
    public var reportText = ""
    public init() {}
}

public struct Restaurant: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var note: String
    public init(id: UUID = UUID(), name: String, note: String = "") {
        self.id = id; self.name = name; self.note = note
    }
}

public struct Dish: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var restaurantID: UUID
    public var name: String
    public var tags: [String]
    public var allergens: [String]
    public var ingredientsVerified: Bool
    public var price: Double?
    public init(id: UUID = UUID(), restaurantID: UUID, name: String, tags: [String] = [],
                allergens: [String] = [], ingredientsVerified: Bool = false, price: Double? = nil) {
        self.id = id; self.restaurantID = restaurantID; self.name = name; self.tags = tags
        self.allergens = allergens; self.ingredientsVerified = ingredientsVerified; self.price = price
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
    public var schemaVersion = 1
    public var events: [CalendarEvent] = []
    public var restaurants: [Restaurant] = []
    public var dishes: [Dish] = []
    public var meals: [MealLog] = []
    public var reminderRecords: [ReminderRecord] = []
    public var profile = HealthProfile()
    public var acceptedAdvice: String = ""
    public var agentBaseURL = "https://api.openai.com/v1"
    public var agentModel = "gpt-4.1-mini"
    public var avoidRecentMeals = true
    public init() {}
}
