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

    @Published private(set) var isBootstrapping = true

    override init() {
        let savedServer = Self.initialServerAddress()
        self.pendingServer = savedServer
        super.init()

        Task { await self.bootstrap() }
    }

    var isSignedIn: Bool { session != nil }

    /// Test-user sign-in is only offered on a dev instance (loopback).
    var showsDevSignIn: Bool {
        Self.pointsAtLoopback(pendingServer)
    }

    func signInAsTestUser() {
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
                let signedInSession = try await client.devSignIn(server: trimmed)
                try await self.completeSignIn(signedInSession)
            } catch {
                self.finish(error: error)
            }
        }
    }

    private static func initialServerAddress() -> String {
        if let argument = launchArgumentValue(named: "-hive-server"), !argument.isEmpty {
            return argument
        }
        if let env = ProcessInfo.processInfo.environment["HIVE_SERVER"], !env.isEmpty {
            return env
        }
        if let saved = UserDefaults.standard.string(forKey: userDefaultsServerKey), !saved.isEmpty {
            return saved
        }
        return defaultServerURL
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

    func bootstrap() async {
        defer { isBootstrapping = false }
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

    func loadErrors() async throws -> [HiveErrorIssue] {
        try await loadResource(.errors)
    }

    func loadSpecs() async throws -> [HiveSpec] {
        try await loadResource(.specs)
    }

    private func loadResource<Value: Decodable>(_ resource: HiveResource) async throws -> Value {
        guard let session else {
            throw MobileClientError("Sign in to Hive to browse this resource.")
        }
        let result: ResourceResult<Value> = try await client.resource(resource, session: session)
        try credentialStore.save(result.session)
        self.session = result.session
        return result.value
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
