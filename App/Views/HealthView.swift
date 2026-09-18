import SwiftUI
import UniformTypeIdentifiers

struct HealthView: View {
    @EnvironmentObject private var store: AppStore
    @State private var report = ""; @State private var showingFile = false; @State private var advice: AdviceResponse?
    @State private var isAnalyzing = false; @State private var key = ""
    @State private var isConnectingHealth = false
    @State private var healthStatus: String?
    var body: some View { NavigationStack { Form {
        Section("今日健康") { Toggle("喝水提醒", isOn: $store.snapshot.profile.waterEnabled); if store.snapshot.profile.waterEnabled { Stepper("每 \(store.snapshot.profile.waterIntervalMinutes) 分钟 · \(store.snapshot.profile.waterAmountML) ml", value: $store.snapshot.profile.waterIntervalMinutes, in: 30...240, step: 15) }; Toggle("运动提醒", isOn: $store.snapshot.profile.exerciseEnabled); if store.snapshot.profile.exerciseEnabled { Picker("运动", selection: $store.snapshot.profile.exerciseKind) { ForEach(WorkoutKind.allCases) { Text($0.title).tag($0) } }; Stepper("\(store.snapshot.profile.exerciseMinutes) 分钟", value: $store.snapshot.profile.exerciseMinutes, in: 10...180, step: 5) }; Toggle("睡觉提醒", isOn: $store.snapshot.profile.sleepEnabled) }
        Section("体检资料或健康描述") { TextEditor(text: $report).frame(minHeight: 110); HStack { Button("导入文本报告") { showingFile = true }; Button { Task { await analyze() } } label: { if isAnalyzing { ProgressView() } else { Text("生成建议") } }.disabled(report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing) }; Text("建议会先显示在这里，确认后才保存。\n不替代医生诊断。" ).font(.caption).foregroundStyle(.secondary) }
        if let advice { Section("待确认的生活建议") { ForEach(advice.extracted, id: \.self) { Text("识别：\($0)") }; ForEach(advice.advice, id: \.self) { Text("• \($0)") }; ForEach(advice.cautions, id: \.self) { Text("注意：\($0)").foregroundStyle(.orange) }; Button("采纳并保存") { store.snapshot.acceptedAdvice = advice.advice.joined(separator: "\n"); store.snapshot.profile.reportText = report } } }
        Section("Apple 健康") {
            Button {
                Task {
                    isConnectingHealth = true
                    defer { isConnectingHealth = false }
                    do {
                        let health = HealthKitService()
                        let result = try await health.requestAccess()
                        let todayWorkouts = try await health.workouts(on: Date())
                        switch result {
                        case .authorizationRequested:
                            healthStatus = "授权完成，今日已读取到 \(todayWorkouts.count) 条运动记录。"
                            store.banner = "Apple 健康已连接"
                        case .alreadyHandled:
                            healthStatus = "健康数据查询完成，今日读取到 \(todayWorkouts.count) 条运动记录。若应有记录但为 0，请到“健康 App → 头像 → App 与服务 → Mr. Calender”检查权限。"
                            store.banner = "Apple 健康已连接"
                        case .unknown:
                            healthStatus = "健康数据查询完成，今日读取到 \(todayWorkouts.count) 条运动记录；系统授权状态暂时无法判断。"
                            store.banner = "Apple 健康查询完成"
                        }
                    } catch {
                        healthStatus = "连接失败：\(error.localizedDescription)"
                        store.banner = error.localizedDescription
                    }
                }
            } label: {
                if isConnectingHealth { ProgressView().progressViewStyle(.circular) } else { Label("连接 Apple 健康", systemImage: "heart.text.square") }
            }.disabled(isConnectingHealth)
            if let healthStatus { Text(healthStatus).font(.caption).foregroundStyle(.secondary) }
            Text("Apple Watch 的运动记录只有在授权并匹配目标后才会用于自动打卡。") .font(.caption).foregroundStyle(.secondary)
        }
    }.navigationTitle("健康") }.fileImporter(isPresented: $showingFile, allowedContentTypes: [.plainText, .pdf, .image], allowsMultipleSelection: false) { result in if case .success(let urls) = result, let url = urls.first { if url.pathExtension.lowercased() == "txt" { report = (try? String(contentsOf: url, encoding: .utf8)) ?? "" } else { Task { do { report = try await ReportExtractor.text(from: url) } catch { store.banner = "报告识别失败：\(error.localizedDescription)" } } } } } }
    private func analyze() async { isAnalyzing = true; defer { isAnalyzing = false }; let token = key.isEmpty ? (KeychainStore.shared.read(account: "deepseek-api-key") ?? "") : key; guard !token.isEmpty else { store.banner = "请在设置中保存 DeepSeek API Key"; return }; do { advice = try await AIService().analyze(text: report, baseURL: store.snapshot.agentBaseURL, model: store.snapshot.agentModel, apiKey: token) } catch { store.banner = "分析失败：\(error.localizedDescription)" } }
}
