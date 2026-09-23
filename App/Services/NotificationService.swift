import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    func requestAccess() async -> Bool { (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false }
    func schedule(_ reminders: [PlannedReminder]) async {
        let queue = SchedulePlanner.notificationQueue(reminders, after: Date())
        await PendingNotificationReplacement.replace(
            queue,
            removeAllPending: { center.removeAllPendingNotificationRequests() },
            isAuthorized: {
                let settings = await center.notificationSettings()
                return settings.authorizationStatus == .authorized
            },
            add: { reminder in
                let content = UNMutableNotificationContent(); content.title = reminder.title; content.body = reminder.detail; content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false)
                let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
                try? await center.add(request)
            }
        )
    }
}
