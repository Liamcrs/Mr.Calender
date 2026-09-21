import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var key = ""; @State private var showKey = false
    var body: some View { NavigationStack { Form { Section("DeepSeek 健康 Agent") { TextField("API 地址", text: $store.snapshot.agentBaseURL); TextField("模型", text: $store.snapshot.agentModel); SecureField("API Key（只存钥匙串）", text: $key); Button("保存 Key") { try? KeychainStore.shared.save(key, account: "deepseek-api-key"); key = ""; store.banner = "Key 已保存到本机钥匙串" }; Text("API Key 只保存在本机钥匙串。健康对话仅用于生活方式建议，不替代医生诊断。") .font(.caption).foregroundStyle(.secondary) }
        Section("提醒") { Button("允许系统通知") { Task { let granted = await NotificationService.shared.requestAccess(); if granted { store.scheduleNotifications() }; store.banner = granted ? "系统通知已启用" : "系统通知未获允许，请到设置中打开" } }; Toggle("转盘一天内不重复", isOn: $store.snapshot.avoidRecentMeals) }
        Section("隐私与发布") { Text("数据默认保存在本机应用沙盒。发布到 App Store 前需要在 Xcode 配置 HealthKit capability、通知权限说明、签名和隐私清单。") .font(.caption).foregroundStyle(.secondary) }
    }.dismissKeyboardOnTap().navigationTitle("设置") } }
}
