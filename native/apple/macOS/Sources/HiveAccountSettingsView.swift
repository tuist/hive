import SwiftUI

struct HiveAccountSettingsView: View {
    @EnvironmentObject private var accountStore: HiveAccountStore

    var body: some View {
        Form {
            Section {
                if let user = accountStore.user, let server = accountStore.server {
                    LabeledContent("Signed in as") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(user.email).font(.body)
                            Text(user.role.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Server", value: server)
                    HStack {
                        Spacer()
                        Button("Sign out", role: .destructive) {
                            accountStore.signOut()
                        }
                    }
                } else {
                    TextField(
                        "Server address",
                        text: $accountStore.pendingServer,
                        prompt: Text("https://hive.example.com")
                    )
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)

                    if let error = accountStore.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Spacer()
                        Button {
                            accountStore.signIn()
                        } label: {
                            if accountStore.isSigningIn {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Sign in with Hive")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(accountStore.isSigningIn)
                    }
                }
            } header: {
                Text("Hive account")
            } footer: {
                Text(
                    "Hive opens your browser to sign in and stores the resulting session in the macOS Keychain."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
