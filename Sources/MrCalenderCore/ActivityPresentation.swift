import Foundation

public struct DailyActivitySummary: Equatable, Sendable {
    public let date: Date
    public let activeEnergy: Double
    public let activeEnergyGoal: Double
    public let exerciseMinutes: Double
    public let exerciseGoal: Double
    public let standHours: Double
    public let standGoal: Double

    public init(date: Date, activeEnergy: Double, activeEnergyGoal: Double,
                exerciseMinutes: Double, exerciseGoal: Double,
                standHours: Double, standGoal: Double) {
        self.date = date
        self.activeEnergy = activeEnergy
        self.activeEnergyGoal = activeEnergyGoal
        self.exerciseMinutes = exerciseMinutes
        self.exerciseGoal = exerciseGoal
        self.standHours = standHours
        self.standGoal = standGoal
    }

    public var moveProgress: Double { Self.progress(activeEnergy, goal: activeEnergyGoal) }
    public var exerciseProgress: Double { Self.progress(exerciseMinutes, goal: exerciseGoal) }
    public var standProgress: Double { Self.progress(standHours, goal: standGoal) }

    private static func progress(_ value: Double, goal: Double) -> Double {
        guard value.isFinite, goal.isFinite, value > 0, goal > 0 else { return 0 }
        return min(1, value / goal)
    }
}

public struct DailyActivityMetrics: Equatable, Sendable {
    public let date: Date
    public let activeEnergy: Double?
    public let exerciseMinutes: Double?
    public let standHours: Double?

    public init(date: Date, activeEnergy: Double?, exerciseMinutes: Double?, standHours: Double?) {
        self.date = date
        self.activeEnergy = activeEnergy
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
    }
}

public struct ActivityDay: Equatable, Sendable {
    public let date: Date
    public let summary: DailyActivitySummary?
    public let records: [WorkoutRecord]

    public var workoutText: String {
        guard let first = records.first else { return "无训练记录" }
        if records.count == 1 {
            return "\(first.title) \(first.minutes) 分钟 · \(first.source.title)"
        }
        return "\(first.title) \(first.minutes) 分钟等 \(records.count) 项"
    }
}

public enum ActivityPresentation {
    public static func historicalSummaries(
        _ summaries: [DailyActivitySummary], excluding today: Date, calendar: Calendar
    ) -> [DailyActivitySummary] {
        summaries.filter { !calendar.isDate($0.date, inSameDayAs: today) }
    }

    public static func standHourCount(sampleDates: [Date], calendar: Calendar) -> Int {
        Set(sampleDates.map {
            calendar.dateComponents([.era, .year, .month, .day, .hour], from: $0)
        }).count
    }

    public static func values(
        summary: DailyActivitySummary?, measured: DailyActivityMetrics?
    ) -> DailyActivityMetrics? {
        guard let summary else { return measured }
        return DailyActivityMetrics(
            date: summary.date,
            activeEnergy: summary.activeEnergy,
            exerciseMinutes: summary.exerciseMinutes,
            standHours: summary.standHours
        )
    }

    public static func days(today: Date, summaries: [DailyActivitySummary],
                            records: [WorkoutRecord], calendar: Calendar) -> [ActivityDay] {
        let start = calendar.startOfDay(for: today)
        return (0..<4).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: start)!
            let summary = summaries.first { calendar.isDate($0.date, inSameDayAs: date) }
            let dayRecords = records.filter { calendar.isDate($0.date, inSameDayAs: date) }
            return ActivityDay(date: date, summary: summary, records: dayRecords)
        }
    }

    public static func dateLabel(_ date: Date, relativeTo today: Date,
                                 calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        let template = calendar.component(.year, from: date) == calendar.component(.year, from: today)
            ? "Md" : "yMd"
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
