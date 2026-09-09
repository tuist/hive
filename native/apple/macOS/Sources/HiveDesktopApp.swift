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
    @StateObject private var hiveAccount = HiveAccountStore()
    @StateObject private var hiveOverview = HiveOverviewStore()

    var body: some Scene {
        WindowGroup {
            HiveDesktopRootScene()
                .environmentObject(themeStore)
                .environmentObject(inferenceAccounts)
                .environmentObject(agentRuntime)
                .environmentObject(hiveAccount)
                .environmentObject(hiveOverview)
                .hiveWorkTheme(themeStore.selectedTheme)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
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
                .environmentObject(hiveAccount)
                .environmentObject(hiveOverview)
                .hiveWorkTheme(themeStore.selectedTheme)
        }
    }
}

private struct HiveDesktopRootScene: View {
    @EnvironmentObject private var account: HiveAccountStore
    @EnvironmentObject private var overview: HiveOverviewStore

    var body: some View {
        Group {
            if account.isBootstrapping {
                ProgressView()
                    .controlSize(.large)
                    .frame(width: 480, height: 320)
            } else if account.isSignedIn {
                HiveWorkRootView()
                    .frame(minWidth: 800, minHeight: 500)
                    .task { await overview.reload(using: account) }
            } else {
                HiveDesktopLoginView()
                    .frame(minWidth: 480, idealWidth: 520, minHeight: 640, idealHeight: 700)
            }
        }
        .onChange(of: account.isSignedIn) { _, signedIn in
            if signedIn {
                Task { await overview.reload(using: account) }
            } else {
                overview.clear()
            }
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
