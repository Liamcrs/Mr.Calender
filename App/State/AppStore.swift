import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var snapshot: AppSnapshot { didSet { save(); if isReady { refreshReminders() } } }
    @Published var selectedDate = Date()
    @Published var reminders: [PlannedReminder] = []
    @Published var banner: String? { didSet { restartBannerDismissal() } }
    private let url: URL
    private let photosDirectory: URL
    private let calendar: Calendar
    private var isReady = false
    private var bannerDismissTask: Task<Void, Never>?

    init() {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current; calendar = c
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("snapshot.json")
        photosDirectory = support.appendingPathComponent("DishPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url), let loaded = try? SnapshotStore.decode(data) { snapshot = loaded } else { snapshot = AppSnapshot() }
        isReady = true
        refreshReminders()
    }

    func save() {
        do { let data = try SnapshotStore.encode(snapshot); try data.write(to: url, options: [.atomic, .completeFileProtection]) }
        catch { banner = "本地保存失败：\(error.localizedDescription)" }
    }
    func refreshReminders() {
        let from = calendar.startOfDay(for: selectedDate)
        let to = calendar.date(byAdding: .day, value: 7, to: from)!
        reminders = SchedulePlanner.reminders(snapshot, from: from, to: to, calendar: calendar)
        if isReady { scheduleNotifications() }
    }
    func scheduleNotifications() { let queue = reminders; Task { await NotificationService.shared.schedule(queue) } }
    func setReminder(_ reminder: PlannedReminder, status: ReminderStatus, snoozedUntil: Date? = nil) {
        snapshot.reminderRecords.removeAll { $0.id == reminder.id }
        snapshot.reminderRecords.append(.init(id: reminder.id, status: status, snoozedUntil: snoozedUntil))
        refreshReminders()
    }
    func addEvent(title: String, date: Date, duration: TimeInterval = 3600, notes: String = "") {
        snapshot.events.append(.init(title: title, startsAt: date, endsAt: date.addingTimeInterval(duration), notes: notes))
        refreshReminders()
    }
    func addDishPhoto(data: Data) throws -> String {
        let name = "\(UUID().uuidString).jpg"
        try data.write(to: photosDirectory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }
    func photoURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty, URL(fileURLWithPath: path).lastPathComponent == path else { return nil }
        return photosDirectory.appendingPathComponent(path)
    }
    func deleteRestaurant(id: UUID) {
        let photoPaths = snapshot.removeRestaurant(id: id)
        for path in photoPaths {
            guard let url = photoURL(for: path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        banner = "已删除饭店及其菜品"
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

    private func restartBannerDismissal() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        guard banner != nil else { return }
        bannerDismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }
}
