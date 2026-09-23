import SwiftUI
import HealthKit

struct HealthView: View {
    @EnvironmentObject private var store: AppStore
    @State private var message = ""
    @State private var isSending = false
    @State private var isConnectingHealth = false
    @State private var healthStatus: String?
    @State private var healthRecords: [WorkoutRecord] = []
    @State private var activitySummaries: [DailyActivitySummary] = []
    @State private var activityStatus: String?
    @State private var showingAddWorkout = false

    private static let healthService = HealthKitService()

    private var activityRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (calendar.date(byAdding: .day, value: -3, to: today)!, today)
    }

    private var activityDays: [ActivityDay] {
        ActivityPresentation.days(
            today: Date(),
            summaries: activitySummaries,
            records: allRecords,
            calendar: .current
        )
    }

    private var historyRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        return (start, end)
    }

    private var allRecords: [WorkoutRecord] {
        WorkoutHistory.records(
            manual: store.snapshot.manualWorkouts,
            health: healthRecords,
            from: historyRange.start,
            to: historyRange.end
        )
    }

    private var todayRecords: [WorkoutRecord] {
        allRecords.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            Form {
                workoutSection
                waterSection
                sleepSection
                agentSection
            }
            .dismissKeyboardOnTap()
            .navigationTitle("健康")
            .task { await refreshHealth(requestAccess: false, announceEmpty: false) }
            .refreshable { await refreshHealth(requestAccess: false, announceEmpty: true) }
            .sheet(isPresented: $showingAddWorkout) {
                AddWorkoutView { workout in
                    store.snapshot.manualWorkouts.append(workout)
                    store.banner = "已记录 \(workout.kind.title)"
                }
            }
        }
    }

    private var waterSection: some View {
        Section("喝水提醒") {
            TextField("提醒间隔（分钟）", value: $store.snapshot.profile.waterIntervalMinutes, format: .number)
                .keyboardType(.numberPad)
            TextField("每次摄入（毫升）", value: $store.snapshot.profile.waterAmountML, format: .number)
                .keyboardType(.numberPad)
            Text("默认开启；提醒只安排在起床后至建议入睡前。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sleepSection: some View {
        Section("睡眠提醒") {
            TextField("目标睡眠时长（小时）", value: $store.snapshot.profile.sleepHours,
                      format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
            TextField("提前准备时间（分钟）", value: $store.snapshot.profile.preparationMinutes, format: .number)
                .keyboardType(.numberPad)
            Text("系统会根据明天最早的课程或自定义安排倒推起床与最晚入睡时间，并在入睡前 30、20、10 分钟提醒。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var workoutSection: some View {
        Section("今日运动记录") {
            ActivitySummaryCard(days: activityDays, today: Date())

            if let activityStatus {
                Text(activityStatus)
                    .font(.caption)
                    .foregroundStyle(activityStatus.hasPrefix("活动摘要读取失败") ? .red : .secondary)
            }

            Button { Task { await refreshHealth(requestAccess: true, announceEmpty: true) } } label: {
                if isConnectingHealth {
                    HStack { ProgressView(); Text("正在读取…") }
                } else {
                    Label("读取 Apple 健康", systemImage: "heart.text.square")
                }
            }
            .disabled(isConnectingHealth)

            if let healthStatus {
                Text(healthStatus)
                    .font(.caption)
                    .foregroundStyle(healthStatus.hasPrefix("运动记录读取失败") ? .red : .secondary)
            }

            if todayRecords.isEmpty {
                Text("今天还没有运动记录。可从 Apple 健康读取，或手动补录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todayRecords) { WorkoutRecordRow(record: $0) }
            }

            Button { showingAddWorkout = true } label: {
                Label("手动补录运动", systemImage: "plus.circle")
            }

            NavigationLink {
                WorkoutHistoryView(
                    healthRecords: healthRecords,
                    start: historyRange.start,
                    end: historyRange.end
                )
            } label: {
                HStack {
                    Label("全部运动记录", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Text("近 30 天 \(allRecords.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var agentSection: some View {
        Section("健康问诊 Agent") {
            ForEach(store.snapshot.healthChat) { chat in
                HStack(alignment: .top) {
                    Text(chat.role == .user ? "我" : "Agent")
                        .font(.caption.bold())
                        .foregroundStyle(chat.role == .user ? .blue : .green)
                    Text(chat.content).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            TextEditor(text: $message).frame(minHeight: 90)
            Button { Task { await sendMessage() } } label: {
                if isSending { ProgressView() }
                else { Label("发送给健康 Agent", systemImage: "paperplane.fill") }
            }
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            Text("仅提供生活方式建议，不替代医生诊断；请勿发送不必要的敏感身份信息。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshHealth(requestAccess: Bool, announceEmpty: Bool) async {
        isConnectingHealth = true
        defer { isConnectingHealth = false }
        do {
            if requestAccess { _ = try await Self.healthService.requestAccess() }
        } catch {
            let message = "健康权限请求失败：\(error.localizedDescription)"
            healthStatus = message
            activityStatus = message
            if requestAccess { store.banner = message }
            return
        }

        do {
            let workouts = try await Self.healthService.workouts(from: historyRange.start, to: historyRange.end)
            healthRecords = workouts.map(workoutRecord)
            healthStatus = healthRecords.isEmpty && announceEmpty
                ? "近 30 天未读取到运动，请检查健康权限和 Apple Watch 同步。"
                : healthRecords.isEmpty ? nil : "已读取近 30 天 \(healthRecords.count) 条运动。"
        } catch {
            healthStatus = "运动记录读取失败：\(error.localizedDescription)"
        }

        do {
            activitySummaries = try await Self.healthService.activitySummaries(
                from: activityRange.start,
                to: activityRange.end,
                calendar: .current
            )
            activityStatus = activitySummaries.isEmpty
                ? "未读取到活动摘要，请检查健康权限和 Apple Watch 同步。"
                : nil
        } catch {
            activityStatus = "活动摘要读取失败：\(error.localizedDescription)"
        }

        if requestAccess {
            if !healthRecords.isEmpty || !activitySummaries.isEmpty {
                store.banner = "Apple 健康记录已更新"
            } else if healthStatus?.hasPrefix("运动记录读取失败") != true
                && activityStatus?.hasPrefix("活动摘要读取失败") != true {
                store.banner = "未读取到健康数据，请检查权限和 Apple Watch 同步"
            }
        }
    }

    private func workoutRecord(_ workout: HKWorkout) -> WorkoutRecord {
        let distance = workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
        return WorkoutRecord(
            id: "health-\(workout.uuid.uuidString)",
            kind: workoutKind(workout.workoutActivityType),
            minutes: max(1, Int((workout.duration / 60).rounded())),
            distanceKM: max(0, distance),
            source: .appleHealth,
            date: workout.startDate
        )
    }

    private func workoutKind(_ activity: HKWorkoutActivityType) -> WorkoutKind {
        switch activity {
        case .walking: return .walking
        case .running: return .running
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .basketball: return .basketball
        case .badminton: return .badminton
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strengthTraining
        case .hiking: return .hiking
        default: return .other
        }
    }

    private func sendMessage() async {
        let content = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let key = KeychainStore.shared.read(account: "deepseek-api-key"), !key.isEmpty else {
            store.banner = "请先在设置中保存 DeepSeek API Key"
            return
        }
        message = ""
        isSending = true
        defer { isSending = false }
        store.snapshot.healthChat.append(.init(role: .user, content: content))
        do {
            let reply = try await AIService().chat(
                messages: store.snapshot.healthChat,
                baseURL: store.snapshot.agentBaseURL,
                model: store.snapshot.agentModel,
                apiKey: key
            )
            store.snapshot.healthChat.append(.init(role: .assistant, content: reply))
        } catch {
            store.banner = "健康 Agent 暂时无法回复：\(error.localizedDescription)"
        }
    }
}

private struct WorkoutRecordRow: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.kind.systemImage)
                .foregroundStyle(record.source == .appleHealth ? .red : .green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.title).font(.subheadline.bold())
                    Text(record.source.title)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                HStack(spacing: 8) {
                    Text("\(record.minutes) 分钟")
                    if record.distanceKM > 0.01 {
                        Text("\(record.distanceKM, specifier: "%.2f") 公里")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(record.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct WorkoutHistoryView: View {
    @EnvironmentObject private var store: AppStore
    let healthRecords: [WorkoutRecord]
    let start: Date
    let end: Date

    private var records: [WorkoutRecord] {
        WorkoutHistory.records(
            manual: store.snapshot.manualWorkouts,
            health: healthRecords,
            from: start,
            to: end
        )
    }

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "暂无运动记录",
                    systemImage: "figure.walk",
                    description: Text("返回健康页读取 Apple 健康，或手动补录运动。")
                )
            } else {
                List(records) { record in
                    WorkoutRecordRow(record: record)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if record.source == .manual {
                                Button("删除", role: .destructive) { deleteManualWorkout(record) }
                            }
                        }
                }
            }
        }
        .navigationTitle("运动记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteManualWorkout(_ record: WorkoutRecord) {
        store.snapshot.manualWorkouts.removeAll { "manual-\($0.id.uuidString)" == record.id }
        store.banner = "已删除手动运动记录"
    }
}

private struct AddWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ManualWorkout) -> Void

    @State private var kind: WorkoutKind = .walking
    @State private var date = Date()
    @State private var minutes = 30
    @State private var distanceKM = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("运动信息") {
                    Picker("类型", selection: $kind) {
                        ForEach(WorkoutKind.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("时间", selection: $date, in: ...Date())
                    Stepper("时长：\(minutes) 分钟", value: $minutes, in: 1...600, step: 5)
                    TextField("距离（公里，可选）", value: $distanceKM,
                              format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                }
                Section {
                    Text("手动记录只保存在本机，不会写入 Apple 健康。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("补录运动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(ManualWorkout(
                            kind: kind,
                            minutes: minutes,
                            distanceKM: max(0, distanceKM),
                            date: date
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension WorkoutKind {
    var systemImage: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .basketball: return "figure.basketball"
        case .badminton: return "figure.badminton"
        case .strengthTraining: return "dumbbell.fill"
        case .hiking: return "figure.hiking"
        case .other: return "figure.mixed.cardio"
        }
    }
}
