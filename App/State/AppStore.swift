import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var snapshot: AppSnapshot { didSet { save() } }
    @Published var selectedDate = Date()
    @Published var reminders: [PlannedReminder] = []
    @Published var banner: String?
    private let url: URL
    private let calendar: Calendar

    init() {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current; calendar = c
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("snapshot.json")
        if let data = try? Data(contentsOf: url), let loaded = try? SnapshotStore.decode(data) { snapshot = loaded } else { snapshot = AppSnapshot() }
        refreshReminders()
    }

    func save() {
        do { let data = try SnapshotStore.encode(snapshot); try data.write(to: url, options: [.atomic, .completeFileProtection]) }
        catch { banner = "本地保存失败：\(error.localizedDescription)" }
    }
    func refreshReminders() {
        let from = calendar.startOfDay(for: selectedDate)
        let to = calendar.date(byAdding: .day, value: 2, to: from)!
        reminders = SchedulePlanner.reminders(snapshot, from: from, to: to, calendar: calendar)
    }
    func setReminder(_ reminder: PlannedReminder, status: ReminderStatus, snoozedUntil: Date? = nil) {
        snapshot.reminderRecords.removeAll { $0.id == reminder.id }
        snapshot.reminderRecords.append(.init(id: reminder.id, status: status, snoozedUntil: snoozedUntil))
        refreshReminders()
    }
    func addEvent(title: String, date: Date, duration: TimeInterval = 3600) {
        snapshot.events.append(.init(title: title, startsAt: date, endsAt: date.addingTimeInterval(duration)))
        refreshReminders()
    }
    func importICS(_ text: String) {
        do {
            let from = calendar.startOfDay(for: selectedDate), to = calendar.date(byAdding: .year, value: 1, to: from)!
            let result = try ICSParser.parse(text, from: from, to: to, timeZone: calendar.timeZone)
            snapshot.events.removeAll { event in event.importedUID.map(result.importedUIDs.contains) ?? false }
            snapshot.events.append(contentsOf: result.events)
            banner = "已导入 \(result.events.count) 项课程"
            refreshReminders()
        } catch { banner = "课表导入失败：\(error.localizedDescription)" }
    }
}
