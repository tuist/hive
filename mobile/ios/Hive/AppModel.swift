import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase {
        case launching
        case signedOut
        case signedIn
    }

    @Published private(set) var phase = Phase.launching
    @Published private(set) var user: HiveUser?
    @Published private(set) var server: String?

    private let credentialStore = CredentialStore()
    private let oauthClient = OAuthClient()
    private let apiClient = HiveAPIClient()
    private var credentials: OAuthSession?

    func bootstrap() async {
        guard case .launching = phase else { return }

        do {
            guard let saved = try credentialStore.load() else {
                phase = .signedOut
                return
            }
            let refreshed = try await oauthClient.refresh(saved)
            try credentialStore.save(refreshed)
            let currentUser = try await apiClient.currentUser(using: refreshed)
            credentials = refreshed
            user = currentUser
            server = try oauthClient.server(refreshed)
            phase = .signedIn
        } catch {
            try? credentialStore.clear()
            credentials = nil
            user = nil
            server = nil
            phase = .signedOut
        }
    }

    func completeSignIn(_ session: OAuthSession) async throws {
        let currentUser = try await apiClient.currentUser(using: session)
        try credentialStore.save(session)
        credentials = session
        user = currentUser
        server = try oauthClient.server(session)
        phase = .signedIn
    }

    func loadForage() async throws -> [ForageItem] {
        let session = try await validSession()
        return try await apiClient.forage(using: session)
    }

    func loadSpecs() async throws -> [HiveSpec] {
        let session = try await validSession()
        return try await apiClient.specs(using: session)
    }

    func loadDrops() async throws -> [HiveDrop] {
        let session = try await validSession()
        return try await apiClient.drops(using: session)
    }

    func loadDropDigests() async throws -> [DropDigest] {
        let session = try await validSession()
        return try await apiClient.dropDigests(using: session)
    }

    func signOut() async {
        if let credentials {
            try? await oauthClient.revoke(credentials)
        }
        try? credentialStore.clear()
        credentials = nil
        user = nil
        server = nil
        phase = .signedOut
    }

    private func validSession() async throws -> OAuthSession {
        guard var credentials else {
            throw OAuthClientError("The sign-in session is missing.")
        }
        if try oauthClient.shouldRefresh(credentials) {
            credentials = try await oauthClient.refresh(credentials)
            try credentialStore.save(credentials)
            self.credentials = credentials
        }
        return credentials
    }
}
