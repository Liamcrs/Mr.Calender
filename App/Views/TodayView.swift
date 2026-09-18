import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Date.now, format: .dateTime.weekday(.wide).month().day()).font(.subheadline).foregroundStyle(.secondary)
                        Text("今天，照顾好自己").font(.largeTitle.bold())
                        Text("未来 7 天的安排都可以提前完成").font(.caption).foregroundStyle(.secondary)
                    }
                    let days = Dictionary(grouping: store.reminders, by: { calendar.startOfDay(for: $0.date) })
                    if days.isEmpty {
                        SectionCard(title: "计划") { Text("未来 7 天还没有需要提醒的安排").foregroundStyle(.secondary) }
                    } else {
                        ForEach(days.keys.sorted(), id: \.self) { day in
                            SectionCard(title: dayTitle(day)) {
                                ForEach(days[day] ?? []) { reminder in ReminderRow(reminder: reminder) }
                            }
                        }
                    }
                    let events = store.snapshot.events.filter { $0.startsAt >= Date() && $0.startsAt < calendar.date(byAdding: .day, value: 7, to: Date())! }.sorted { $0.startsAt < $1.startsAt }
                    if !events.isEmpty {
                        SectionCard(title: "未来课程和自定义安排") {
                            ForEach(events) { event in
                                Label { VStack(alignment: .leading) { Text(event.title); Text(event.startsAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: event.source == .course ? "graduationcap" : "calendar.badge.clock") }
                            }
                        }
                    }
                }.padding()
            }
            .navigationTitle("Mr. Calender")
            .onAppear { store.refreshReminders() }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInTomorrow(day) { return "明天" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

struct ReminderRow: View {
    @EnvironmentObject private var store: AppStore
    let reminder: PlannedReminder
    var body: some View {
        HStack {
            Image(systemName: reminder.kind == .water ? "drop.fill" : reminder.kind == .sleep ? "bed.double.fill" : reminder.kind == .exercise ? "figure.run" : "calendar")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(reminder.title).font(.subheadline.bold())
                Text(reminder.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(reminder.date, format: .dateTime.hour().minute()).font(.caption.monospacedDigit())
            Menu {
                Button("完成") { store.setReminder(reminder, status: .done) }
                Button("稍后 15 分钟") { store.setReminder(reminder, status: .snoozed, snoozedUntil: Date().addingTimeInterval(900)) }
                Button("跳过") { store.setReminder(reminder, status: .skipped) }
            } label: { Image(systemName: "ellipsis.circle") }
        }.padding(.vertical, 3)
    }
}
