import AuthenticationServices
import Foundation
import Security
import SwiftUI

#if os(macOS)
import AppKit
#endif

@MainActor
final class HiveAccountStore: NSObject, ObservableObject {
    static let defaultServerURL = "https://hive.tuist.dev"
    static let redirectURI = "dev.tuist.hive.macos://oauth2redirect"

    private static let userDefaultsServerKey = "dev.tuist.hive.macos.server-url"

    @Published private(set) var user: HiveUser?
    @Published private(set) var server: String?
    @Published var pendingServer: String
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    private let credentialStore = CredentialStore()
    private let client = MobileClient(redirectURI: HiveAccountStore.redirectURI)
    private var session: OAuthSession?
    private var authenticationSession: ASWebAuthenticationSession?

    override init() {
        let savedServer =
            UserDefaults.standard.string(forKey: HiveAccountStore.userDefaultsServerKey)
                ?? HiveAccountStore.defaultServerURL
        self.pendingServer = savedServer
        super.init()

        Task { await self.bootstrap() }
    }

    var isSignedIn: Bool { session != nil }

    func bootstrap() async {
        do {
            guard let saved = try credentialStore.load() else { return }
            let current: ResourceResult<HiveUser> = try await client.resource(
                .currentUser,
                session: saved
            )
            try credentialStore.save(current.session)
            session = current.session
            user = current.value
            let resolved = try client.server(current.session)
            server = resolved
            pendingServer = resolved
        } catch {
            try? credentialStore.clear()
            session = nil
            user = nil
            server = nil
        }
    }

    func signIn() {
        guard !isSigningIn else { return }
        let trimmed = pendingServer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter your Hive server address."
            return
        }

        errorMessage = nil
        isSigningIn = true

        Task {
            do {
                let prepared = try await client.prepare(server: trimmed)
                beginBrowserAuthorization(prepared: prepared)
            } catch {
                finish(error: error)
            }
        }
    }

    func signOut() {
        let signedOutSession = session
        session = nil
        user = nil
        server = nil
        try? credentialStore.clear()

        if let signedOutSession {
            Task { try? await client.signOut(signedOutSession) }
        }
    }

    private func beginBrowserAuthorization(prepared: PreparedAuthorization) {
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
                    self.finish(
                        error: MobileClientError("Hive did not return to the application.")
                    )
                    return
                }

                do {
                    let signedInSession = try await self.client.exchange(
                        callbackURL: callbackURL,
                        pending: prepared.pending
                    )
                    try await self.completeSignIn(signedInSession)
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

    private func completeSignIn(_ signedInSession: OAuthSession) async throws {
        let current: ResourceResult<HiveUser> = try await client.resource(
            .currentUser,
            session: signedInSession
        )
        try credentialStore.save(current.session)
        session = current.session
        user = current.value
        let resolved = try client.server(current.session)
        server = resolved
        pendingServer = resolved
        UserDefaults.standard.set(resolved, forKey: HiveAccountStore.userDefaultsServerKey)
        isSigningIn = false
        errorMessage = nil
    }

    private func finish(error: Error) {
        isSigningIn = false
        if let authenticationError = error as? ASWebAuthenticationSessionError,
           authenticationError.code == .canceledLogin
        {
            errorMessage = nil
        } else {
            errorMessage = error.localizedDescription
        }
    }
}

extension HiveAccountStore: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        let resolve = {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
        }

        if Thread.isMainThread {
            return resolve()
        }
        return DispatchQueue.main.sync(execute: resolve)
        #else
        return ASPresentationAnchor()
        #endif
    }
}
