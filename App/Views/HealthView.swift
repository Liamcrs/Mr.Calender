import SwiftUI
import HealthKit

private struct WorkoutSummary: Identifiable {
    let id: String
    let title: String
    let minutes: Int
    let distanceKM: Double
    let source: String
    let date: Date
}

struct HealthView: View {
    @EnvironmentObject private var store: AppStore
    @State private var message = ""
    @State private var isSending = false
    @State private var isConnectingHealth = false
    @State private var healthStatus: String?
    @State private var todayWorkouts: [WorkoutSummary] = []
    @State private var manualKind: WorkoutKind = .walking
    @State private var manualMinutes = 30
    @State private var manualDistance = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("喝水提醒") {
                    TextField("提醒间隔（分钟）", value: $store.snapshot.profile.waterIntervalMinutes, format: .number)
                        .keyboardType(.numberPad)
                    TextField("每次摄入（毫升）", value: $store.snapshot.profile.waterAmountML, format: .number)
                        .keyboardType(.numberPad)
                    Text("默认开启；可按你的实际摄入量和作息调整。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("睡眠提醒") {
                    TextField("目标睡眠时长（小时）", value: $store.snapshot.profile.sleepHours, format: .number.precision(.fractionLength(1)))
                    TextField("提前准备时间（分钟）", value: $store.snapshot.profile.preparationMinutes, format: .number)
                    Text("系统会根据明天最早的课程或自定义安排倒推起床与最晚入睡时间，并在入睡前 30、20、10 分钟提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("今日运动记录") {
                    Button { Task { await connectHealth() } } label: {
                        if isConnectingHealth { ProgressView().progressViewStyle(.circular) }
                        else { Label("读取 Apple 健康", systemImage: "heart.text.square") }
                    }.disabled(isConnectingHealth)
                    if let healthStatus { Text(healthStatus).font(.caption).foregroundStyle(.secondary) }
                    ForEach(todayWorkouts) { workout in
                        HStack {
                            Image(systemName: "figure.run").foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(workout.title).font(.subheadline.bold())
                                Text("\(workout.minutes) 分钟 · \(workout.distanceKM, specifier: "%.1f") km · \(workout.source)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Text(workout.date, format: .dateTime.hour().minute()).font(.caption)
                        }
                    }
                    Button("手动补录运动") { addManualWorkout() }
                    Picker("类型", selection: $manualKind) { ForEach(WorkoutKind.allCases) { Text($0.title).tag($0) } }
                    Stepper("时长：\(manualMinutes) 分钟", value: $manualMinutes, in: 1...300, step: 5)
                    TextField("距离（公里，可选）", value: $manualDistance, format: .number.precision(.fractionLength(1)))
                }
                Section("健康问诊 Agent") {
                    ForEach(store.snapshot.healthChat) { chat in
                        HStack(alignment: .top) {
                            Text(chat.role == .user ? "我" : "Agent")
                                .font(.caption.bold()).foregroundStyle(chat.role == .user ? .blue : .green)
                            Text(chat.content).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    TextEditor(text: $message).frame(minHeight: 90)
                    Button { Task { await sendMessage() } } label: {
                        if isSending { ProgressView() } else { Label("发送给健康 Agent", systemImage: "paperplane.fill") }
                    }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    Text("仅提供生活方式建议，不替代医生诊断；请勿发送不必要的敏感身份信息。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("健康")
            .task { await loadManualWorkouts() }
        }
    }

    private func addManualWorkout() {
        let record = ManualWorkout(kind: manualKind, minutes: manualMinutes, distanceKM: max(0, manualDistance))
        store.snapshot.manualWorkouts.append(record)
        todayWorkouts.append(.init(id: record.id.uuidString, title: record.kind.title, minutes: record.minutes, distanceKM: record.distanceKM, source: "手动", date: record.date))
        store.banner = "已记录今日运动"
    }

    private func connectHealth() async {
        isConnectingHealth = true; defer { isConnectingHealth = false }
        do {
            let health = HealthKitService()
            let result = try await health.requestAccess()
            let workouts = try await health.workouts(on: Date())
            todayWorkouts = workouts.map { workout in
                let title: String
                switch workout.workoutActivityType {
                case .running: title = "跑步"
                case .swimming: title = "游泳"
                case .basketball: title = "篮球"
                case .walking: title = "步行"
                default: title = "运动"
                }
                let distance = workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
                return WorkoutSummary(id: workout.uuid.uuidString, title: title, minutes: Int(workout.duration / 60), distanceKM: distance, source: "Apple 健康", date: workout.startDate)
            }
            todayWorkouts.append(contentsOf: store.snapshot.manualWorkouts.filter { Calendar.current.isDateInToday($0.date) }.map { .init(id: $0.id.uuidString, title: $0.kind.title, minutes: $0.minutes, distanceKM: $0.distanceKM, source: "手动", date: $0.date) })
            switch result {
            case .authorizationRequested: healthStatus = "授权完成，已读取今日运动记录。"
            case .alreadyHandled: healthStatus = "已读取今日运动记录。"
            case .unknown: healthStatus = "已读取今日运动记录，授权状态由系统管理。"
            }
            store.banner = "Apple 健康已连接"
        } catch { healthStatus = "连接失败：\(error.localizedDescription)"; store.banner = healthStatus }
    }

    private func loadManualWorkouts() async {
        todayWorkouts = store.snapshot.manualWorkouts.filter { Calendar.current.isDateInToday($0.date) }.map { .init(id: $0.id.uuidString, title: $0.kind.title, minutes: $0.minutes, distanceKM: $0.distanceKM, source: "手动", date: $0.date) }
    }

    private func sendMessage() async {
        let content = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let key = KeychainStore.shared.read(account: "deepseek-api-key"), !key.isEmpty else { store.banner = "请先在设置中保存 DeepSeek API Key"; return }
        message = ""; isSending = true; defer { isSending = false }
        store.snapshot.healthChat.append(.init(role: .user, content: content))
        do {
            let reply = try await AIService().chat(messages: store.snapshot.healthChat, baseURL: store.snapshot.agentBaseURL, model: store.snapshot.agentModel, apiKey: key)
            store.snapshot.healthChat.append(.init(role: .assistant, content: reply))
        } catch { store.banner = "健康 Agent 暂时无法回复：\(error.localizedDescription)" }
    }
}
