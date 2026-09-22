import Foundation

@MainActor
public final class LatestNotificationScheduler {
    private let apply: @MainActor ([PlannedReminder]) async -> Void
    private var pending: [PlannedReminder]?
    private var isRunning = false

    public init(apply: @escaping @MainActor ([PlannedReminder]) async -> Void) {
        self.apply = apply
    }

    public func submit(_ reminders: [PlannedReminder]) {
        // An empty array is a replacement too; nil alone means no pending work.
        pending = reminders
        guard !isRunning else { return }
        isRunning = true
        Task {
            while let reminders = pending {
                pending = nil
                // Keep the worker active across suspension so newer submissions only
                // replace pending work; they never start a concurrent apply call.
                await apply(reminders)
            }
            isRunning = false
        }
    }
}
