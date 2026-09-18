import Foundation

public struct SleepPlan: Equatable, Sendable {
    public let wakeAt: Date
    public let bedAt: Date
    public init(wakeAt: Date, bedAt: Date) { self.wakeAt = wakeAt; self.bedAt = bedAt }
}

public struct WorkoutProgress: Equatable, Sendable {
    public let kind: WorkoutKind
    public let minutes: Int
    public let distanceKM: Double
    public init(kind: WorkoutKind, minutes: Int, distanceKM: Double = 0) {
        self.kind = kind; self.minutes = minutes; self.distanceKM = distanceKM
    }
    public func meets(_ profile: HealthProfile) -> Bool {
        kind == profile.exerciseKind && minutes >= profile.exerciseMinutes && distanceKM >= profile.exerciseDistanceKM
    }
}

public enum SchedulePlanner {
    public static func sleepPlan(forMorning morning: Date, profile: HealthProfile, events: [CalendarEvent], calendar: Calendar) -> SleepPlan {
        let morningStart = calendar.startOfDay(for: morning)
        let firstTimedEvent = events.filter { !$0.isAllDay && $0.startsAt >= morningStart && $0.startsAt < calendar.date(byAdding: .day, value: 1, to: morningStart)! }.min { $0.startsAt < $1.startsAt }
        let configuredWake = calendar.date(bySettingHour: profile.wakeMinute / 60, minute: profile.wakeMinute % 60, second: 0, of: morningStart)!
        let wake = firstTimedEvent.map { min(configuredWake, calendar.date(byAdding: .minute, value: -max(0, profile.preparationMinutes), to: $0.startsAt)!) } ?? configuredWake
        let bed = calendar.date(byAdding: .minute, value: -Int(max(1, profile.sleepHours) * 60), to: wake)!
        return SleepPlan(wakeAt: wake, bedAt: bed)
    }

    public static func sleepReminders(forMorning morning: Date, profile: HealthProfile, events: [CalendarEvent], calendar: Calendar) -> [PlannedReminder] {
        let plan = sleepPlan(forMorning: morning, profile: profile, events: events, calendar: calendar)
        return [30, 20, 10].map { minutes in
            let date = plan.bedAt.addingTimeInterval(-Double(minutes * 60))
            return PlannedReminder(id: "sleep-\(Int(plan.bedAt.timeIntervalSince1970))-\(minutes)", kind: .sleep,
                                   title: "准备睡觉", detail: "距离建议入睡还有 \(minutes) 分钟 · 目标睡眠 \(String(format: "%.1f", profile.sleepHours)) 小时", date: date)
        }
    }

    public static func reminders(_ state: AppSnapshot, from start: Date, to end: Date, calendar: Calendar) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for event in state.events where event.startsAt >= start && event.startsAt < end {
            if let minutes = event.reminderMinutes, minutes >= 0 {
                let date = event.startsAt.addingTimeInterval(-Double(minutes * 60))
                result.append(.init(id: "event-\(event.id)-\(Int(event.startsAt.timeIntervalSince1970))", kind: .event, title: event.title, detail: event.location, date: date))
            }
        }
        let profile = state.profile
        if profile.waterEnabled {
            result.append(contentsOf: waterReminders(state, from: start, to: end, calendar: calendar))
        }
        if profile.sleepEnabled {
            var morning = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start))!
            while morning < end {
                result.append(contentsOf: sleepReminders(forMorning: morning, profile: profile, events: state.events, calendar: calendar).filter { $0.date >= start && $0.date < end })
                morning = calendar.date(byAdding: .day, value: 1, to: morning)!
            }
        }
        let records = Dictionary(uniqueKeysWithValues: state.reminderRecords.map { ($0.id, $0) })
        return result.compactMap { reminder in
            guard let record = records[reminder.id] else { return reminder }
            switch record.status {
            case .done, .skipped: return nil
            case .snoozed: guard let date = record.snoozedUntil, date < end else { return reminder }; return .init(id: reminder.id, kind: reminder.kind, title: reminder.title, detail: reminder.detail, date: date)
            }
        }.sorted { $0.date < $1.date }
    }

    private static func waterReminders(_ state: AppSnapshot, from start: Date, to end: Date, calendar: Calendar) -> [PlannedReminder] {
        let interval = TimeInterval(max(30, state.profile.waterIntervalMinutes) * 60)
        let dayStart = calendar.startOfDay(for: start)
        var morning = dayStart
        var result: [PlannedReminder] = []
        while morning < end && result.count < 500 {
            let wake = sleepPlan(forMorning: morning, profile: state.profile, events: state.events, calendar: calendar).wakeAt
            let nextMorning = calendar.date(byAdding: .day, value: 1, to: morning)!
            let bedtime = sleepPlan(forMorning: nextMorning, profile: state.profile, events: state.events, calendar: calendar).bedAt
            let windowStart = max(start, wake)
            let windowEnd = min(end, bedtime)
            if windowStart < windowEnd {
                let elapsed = max(0, windowStart.timeIntervalSince(wake))
                let steps = ceil(elapsed / interval)
                var date = wake.addingTimeInterval(steps * interval)
                while date < windowEnd && result.count < 500 {
                    if !isBusy(date, events: state.events) {
                        let id = "water-\(Int(date.timeIntervalSince1970 / interval))"
                        result.append(.init(id: id, kind: .water, title: "喝水", detail: "约 \(state.profile.waterAmountML) ml", date: date))
                    }
                    date = date.addingTimeInterval(interval)
                }
            }
            morning = nextMorning
        }
        return result
    }

    private static func isBusy(_ date: Date, events: [CalendarEvent]) -> Bool { events.contains { !$0.isAllDay && $0.startsAt <= date && date < $0.endsAt } }
    public static func notificationQueue(_ reminders: [PlannedReminder], after: Date) -> [PlannedReminder] {
        var seen = Set<String>()
        return reminders.filter { $0.date >= after && seen.insert($0.id).inserted }.sorted { $0.date < $1.date }.prefix(60).map { $0 }
    }
}
