import SwiftUI

@main
struct HiveWatchApp: App {
    @StateObject private var nearbyDesktopStore = NearbyDesktopStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section("Nearby Macs") {
                        if nearbyDesktopStore.desktops.isEmpty {
                            Label("No Macs Found", systemImage: "desktopcomputer")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(nearbyDesktopStore.desktops) { desktop in
                                Label(desktop.name, systemImage: "desktopcomputer")
                            }
                        }
                    }

                    Section("Remote Workspaces") {
                        Label("Connect on iPhone", systemImage: "cloud")
                        Text("Your Hive workspaces and sessions will appear here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Hive")
            }
        }
    }
}
