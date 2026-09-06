import AuthenticationServices
import SwiftUI
import UIKit

@MainActor
final class LoginViewModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var serverAddress = "https://hive.tuist.dev"
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let client = MobileClient()
    private let onSignedIn: (OAuthSession) async throws -> Void
    private var authenticationSession: ASWebAuthenticationSession?

    init(onSignedIn: @escaping (OAuthSession) async throws -> Void) {
        self.onSignedIn = onSignedIn
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
            callbackURLScheme: "dev.tuist.hive"
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
