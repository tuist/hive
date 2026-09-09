import SwiftUI

struct HiveDesktopAccountView: View {
    @EnvironmentObject private var account: HiveAccountStore

    var body: some View {
        Form {
            Section {
                if let user = account.user, let server = account.server {
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
                            account.signOut()
                        }
                    }
                } else {
                    TextField(
                        "Server address",
                        text: $account.pendingServer,
                        prompt: Text("https://hive.example.com")
                    )
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)

                    if let error = account.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Spacer()
                        Button {
                            account.signIn()
                        } label: {
                            if account.isSigningIn {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Sign in with Hive")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(account.isSigningIn)
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
        .navigationTitle("Account")
    }
}
