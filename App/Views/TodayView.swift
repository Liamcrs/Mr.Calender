import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) { Text(Date.now, format: .dateTime.weekday(.wide).month().day()).font(.subheadline).foregroundStyle(.secondary); Text("今天，照顾好自己").font(.largeTitle.bold()) }
        SectionCard(title: "下一项安排") { if let next = store.reminders.first(where: { $0.date >= Date() }) { ReminderRow(reminder: next) } else { Text("今天还没有需要提醒的安排").foregroundStyle(.secondary) } }
        SectionCard(title: "生活计划") { ForEach(store.reminders.filter { $0.kind != .event }.prefix(5)) { reminder in ReminderRow(reminder: reminder) } }
        if !store.snapshot.events.filter({ Calendar.current.isDateInToday($0.startsAt) }).isEmpty { SectionCard(title: "今日课程和日程") { ForEach(store.snapshot.events.filter { Calendar.current.isDateInToday($0.startsAt) }.sorted { $0.startsAt < $1.startsAt }) { event in Label(event.title, systemImage: event.source == .course ? "graduationcap" : "calendar.badge.clock").font(.subheadline) } } }
    }.padding() }.navigationTitle("Mr. Calender").toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { _ = await NotificationService.shared.requestAccess(); await NotificationService.shared.schedule(store.reminders) } } label: { Image(systemName: "bell.badge") } } } } }
}

struct ReminderRow: View {
    @EnvironmentObject private var store: AppStore
    let reminder: PlannedReminder
    var body: some View { HStack { Image(systemName: reminder.kind == .water ? "drop.fill" : reminder.kind == .exercise ? "figure.run" : reminder.kind == .sleep ? "bed.double.fill" : "calendar").foregroundStyle(.green); VStack(alignment: .leading) { Text(reminder.title).font(.subheadline.bold()); Text(reminder.detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(reminder.date, format: .dateTime.hour().minute()).font(.caption.monospacedDigit()); Menu { Button("完成") { store.setReminder(reminder, status: .done) }; Button("稍后 15 分钟") { store.setReminder(reminder, status: .snoozed, snoozedUntil: reminder.date.addingTimeInterval(900)) }; Button("跳过") { store.setReminder(reminder, status: .skipped) } } label: { Image(systemName: "ellipsis.circle") } }.padding(.vertical, 3) }
}
