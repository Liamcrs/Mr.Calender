import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        TabView {
            TodayView().tabItem { Label("今日", systemImage: "sun.max.fill") }
            CalendarView().tabItem { Label("日历", systemImage: "calendar") }
            HealthView().tabItem { Label("健康", systemImage: "heart.text.square.fill") }
            FoodView().tabItem { Label("吃什么", systemImage: "fork.knife") }
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .top) {
            if let banner = store.banner {
                Text(banner)
                    .font(.footnote)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.green.opacity(0.18))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.banner)
        .sheet(isPresented: .constant(!store.snapshot.onboardingComplete)) { OnboardingView() }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var sleep = 8.0; @State private var wake = Date(); @State private var allergies = ""
    var body: some View {
        NavigationStack { Form { Section("先设置你的日常") { Text("这些信息只用于生成提醒，可随时修改。")
            Stepper("睡眠目标：\(sleep, specifier: "%.1f") 小时", value: $sleep, in: 4...12, step: 0.5)
            DatePicker("常规起床时间", selection: $wake, displayedComponents: .hourAndMinute)
            TextField("过敏或需要避开的食物（选填）", text: $allergies)
        } }.dismissKeyboardOnTap() .navigationTitle("欢迎使用") .toolbar { ToolbarItem(placement: .confirmationAction) { Button("开始") { var p = store.snapshot.profile; p.sleepHours = sleep; p.wakeMinute = Calendar.current.component(.hour, from: wake) * 60 + Calendar.current.component(.minute, from: wake); p.allergies = allergies.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }; store.snapshot.profile = p; store.snapshot.onboardingComplete = true; dismiss() } } } }
    }
}
