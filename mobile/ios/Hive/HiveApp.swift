import SwiftUI

@main
struct HiveApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch model.phase {
                case .launching:
                    LaunchView()
                case .signedOut:
                    LoginView(onSignedIn: model.completeSignIn)
                case .signedIn:
                    MainTabView()
                }
            }
            .environmentObject(model)
            .task {
                await model.bootstrap()
            }
        }
    }
}
