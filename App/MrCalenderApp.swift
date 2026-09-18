import SwiftUI

@main
struct MrCalenderApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.green)
        }
    }
}
