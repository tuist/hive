import SwiftUI

struct HiveDesktopLoginView: View {
    @EnvironmentObject private var account: HiveAccountStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.indigo.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    HiveDesktopMark()

                    VStack(spacing: 8) {
                        Text("Sign in to Hive")
                            .font(.largeTitle.bold())
                        Text("Connect the desktop app to your Hive deployment.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hive address")
                                .font(.subheadline.weight(.semibold))
                            TextField(
                                "Hive address",
                                text: $account.pendingServer,
                                prompt: Text("https://hive.example.com")
                            )
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                            .onSubmit { account.signIn() }
                        }

                        if let error = account.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Button(action: { account.signIn() }) {
                            HStack {
                                if account.isSigningIn {
                                    ProgressView().controlSize(.small)
                                }
                                Text(account.isSigningIn ? "Connecting…" : "Continue")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            account.isSigningIn
                                || account.pendingServer.trimmingCharacters(in: .whitespaces).isEmpty
                        )

                        if account.showsDevSignIn {
                            Button(action: { account.signInAsTestUser() }) {
                                Text("Sign in as test user")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(.indigo)
                            .disabled(account.isSigningIn)
                        }

                        Label(
                            "Hive opens your browser to sign in securely.",
                            systemImage: "lock.shield"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(24)
                    .frame(maxWidth: 440)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 24, y: 12)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

private struct HiveDesktopMark: View {
    var body: some View {
        Image(systemName: "cube.transparent")
            .font(.system(size: 56, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.orange)
            .padding(14)
            .background(
                Circle().fill(.background.secondary)
            )
            .shadow(color: Color.orange.opacity(0.22), radius: 20, y: 10)
            .accessibilityLabel("Hive")
    }
}
