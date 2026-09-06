import SwiftUI

@main
struct HiveDesktopApp: App {
    @StateObject private var themeStore = HiveWorkThemeStore()
    @StateObject private var inferenceAccounts = InferenceAccountStore()
    @StateObject private var agentRuntime = AgentSessionRuntimeStore()

    var body: some Scene {
        WindowGroup {
            HiveWorkRootView()
                .environmentObject(themeStore)
                .environmentObject(inferenceAccounts)
                .environmentObject(agentRuntime)
                .hiveWorkTheme(themeStore.selectedTheme)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            HiveWorkSettingsView()
                .environmentObject(themeStore)
                .environmentObject(inferenceAccounts)
                .environmentObject(agentRuntime)
                .hiveWorkTheme(themeStore.selectedTheme)
        }
    }
}
