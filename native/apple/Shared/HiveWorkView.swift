import SwiftUI

/// The native work surface that connects Hive's shared product context to
/// local and remote execution sessions.
struct HiveWorkView: View {
    @StateObject private var themeStore = HiveWorkThemeStore()
    @StateObject private var inferenceAccounts = InferenceAccountStore()
    @StateObject private var agentRuntime = AgentSessionRuntimeStore()

    var body: some View {
        HiveWorkRootView()
            .environmentObject(themeStore)
            .environmentObject(inferenceAccounts)
            .environmentObject(agentRuntime)
            .hiveWorkTheme(themeStore.selectedTheme)
    }
}
