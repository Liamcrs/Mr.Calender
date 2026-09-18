import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var key = ""; @State private var showKey = false
    var body: some View { NavigationStack { Form { Section("DeepSeek Agent") { TextField("API 地址", text: $store.snapshot.agentBaseURL); TextField("模型", text: $store.snapshot.agentModel); SecureField("API Key（只存钥匙串）", text: $key); Button("保存 Key") { try? KeychainStore.shared.save(key, account: "deepseek-api-key"); key = ""; store.banner = "Key 已保存到本机钥匙串" }; Text("当前配置：DeepSeek V4 Pro。健康原始数据不会发送；每次分析前由你确认报告文本。") .font(.caption).foregroundStyle(.secondary) }
        Section("提醒") { Button("请求通知权限") { Task { _ = await NotificationService.shared.requestAccess(); store.banner = "已请求通知权限" } }; Toggle("转盘排除近两天吃过的菜", isOn: $store.snapshot.avoidRecentMeals) }
        Section("隐私与发布") { Text("数据默认保存在本机应用沙盒。发布到 App Store 前需要在 Xcode 配置 HealthKit capability、通知权限说明、签名和隐私清单。") .font(.caption).foregroundStyle(.secondary) }
    }.navigationTitle("设置") } }
}
