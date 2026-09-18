import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    func requestAccess() async -> Bool { (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false }
    func schedule(_ reminders: [PlannedReminder]) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let queue = SchedulePlanner.notificationQueue(reminders, after: Date())
        let requests = queue.map { reminder in
            let content = UNMutableNotificationContent(); content.title = reminder.title; content.body = reminder.detail; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false)
            return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        }
        center.removeAllPendingNotificationRequests()
        for request in requests { try? await center.add(request) }
    }
}
