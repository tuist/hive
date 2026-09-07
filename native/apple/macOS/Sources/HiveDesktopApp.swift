import Sparkle
import SwiftUI

@main
struct HiveDesktopApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
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
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            HiveWorkSettingsView()
                .environmentObject(themeStore)
                .environmentObject(inferenceAccounts)
                .environmentObject(agentRuntime)
                .hiveWorkTheme(themeStore.selectedTheme)
        }
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            self?.canCheckForUpdates = updater.canCheckForUpdates
        }
    }
}
