import AuthenticationServices
import SwiftUI
import UIKit

@MainActor
final class LoginViewModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var serverAddress: String
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let client = MobileClient()
    private let onSignedIn: (OAuthSession) async throws -> Void
    private var authenticationSession: ASWebAuthenticationSession?

    static let defaultServerAddress = "https://hive.tuist.dev"

    init(onSignedIn: @escaping (OAuthSession) async throws -> Void) {
        self.onSignedIn = onSignedIn
        serverAddress = Self.initialServerAddress()
    }

    /// Test-user sign-in makes sense only on a dev instance, which is
    /// invariably localhost. We show the button when the address points
    /// at loopback so the option stays hidden in production.
    var showsDevSignIn: Bool {
        Self.pointsAtLoopback(serverAddress)
    }

    func signInAsTestUser() {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true

        Task {
            do {
                let session = try await client.devSignIn(server: serverAddress)
                try await onSignedIn(session)
                isLoading = false
            } catch {
                finish(error: error)
            }
        }
    }

    private static func initialServerAddress() -> String {
        if let argument = launchArgumentValue(named: "-hive-server"),
           !argument.isEmpty
        {
            return argument
        }
        if let env = ProcessInfo.processInfo.environment["HIVE_SERVER"],
           !env.isEmpty
        {
            return env
        }
        return defaultServerAddress
    }

    private static func launchArgumentValue(named name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func pointsAtLoopback(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URLComponents(string: trimmed)?.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    func signIn() {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true

        Task {
            do {
                let prepared = try await client.prepare(server: serverAddress)
                beginBrowserAuthorization(prepared)
            } catch {
                finish(error: error)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func beginBrowserAuthorization(_ prepared: PreparedAuthorization) {
        let session = ASWebAuthenticationSession(
            url: prepared.url,
            callbackURLScheme: client.callbackURLScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.authenticationSession = nil
                if let error {
                    self.finish(error: error)
                    return
                }
                guard let callbackURL else {
                    self.finish(error: MobileClientError("Hive did not return to the application."))
                    return
                }

                do {
                    let session = try await self.client.exchange(
                        callbackURL: callbackURL,
                        pending: prepared.pending
                    )
                    try await self.onSignedIn(session)
                    self.isLoading = false
                } catch {
                    self.finish(error: error)
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authenticationSession = session

        if !session.start() {
            finish(error: MobileClientError("The system browser could not start sign-in."))
        }
    }

    private func finish(error: Error) {
        isLoading = false
        if let authenticationError = error as? ASWebAuthenticationSessionError,
           authenticationError.code == .canceledLogin
        {
            errorMessage = "Sign-in was canceled."
        } else {
            errorMessage = error.localizedDescription
        }
    }
}

struct LoginView: View {
    @StateObject private var model: LoginViewModel

    init(onSignedIn: @escaping (OAuthSession) async throws -> Void) {
        _model = StateObject(wrappedValue: LoginViewModel(onSignedIn: onSignedIn))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.indigo.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 48)

                    HiveMark()

                    VStack(spacing: 10) {
                        Text("Sign in to Hive")
                            .font(.largeTitle.bold())
                        Text("Connect to your organization’s Hive deployment.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hive address")
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                                TextField("https://hive.example.com", text: $model.serverAddress)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("server-address")
                                    .submitLabel(.continue)
                                    .onSubmit(model.signIn)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 52)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            }
                        }

                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("login-error")
                        }

                        Button(action: model.signIn) {
                            HStack {
                                if model.isLoading {
                                    ProgressView().tint(.white)
                                }
                                Text(model.isLoading ? "Connecting…" : "Continue")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(
                            model.isLoading
                                || model.serverAddress.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                        .accessibilityIdentifier("continue-button")

                        if model.showsDevSignIn {
                            Button(action: model.signInAsTestUser) {
                                Text("Sign in as test user")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(.indigo)
                            .disabled(model.isLoading)
                            .accessibilityIdentifier("dev-login-button")
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
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
                    .frame(maxWidth: 480)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

struct HiveMark: View {
    var body: some View {
        Image("HiveLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.orange.opacity(0.22), radius: 20, y: 10)
        .accessibilityLabel("Hive")
    }
}
