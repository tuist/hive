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
    private let client = MobileClient()
    private var credentials: OAuthSession?

    func bootstrap() async {
        guard case .launching = phase else { return }

        do {
            guard let saved = try credentialStore.load() else {
                phase = .signedOut
                return
            }
            let current: ResourceResult<HiveUser> = try await client.resource(
                .currentUser,
                session: saved
            )
            try credentialStore.save(current.session)
            credentials = current.session
            user = current.value
            server = try client.server(current.session)
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
        let current: ResourceResult<HiveUser> = try await client.resource(
            .currentUser,
            session: session
        )
        try credentialStore.save(current.session)
        credentials = current.session
        user = current.value
        server = try client.server(current.session)
        phase = .signedIn
    }

    func loadForage() async throws -> [ForageItem] {
        try await load(.forage, as: [ForageItem].self)
    }

    func loadSpecs() async throws -> [HiveSpec] {
        try await load(.specs, as: [HiveSpec].self)
    }

    func loadDrops() async throws -> [HiveDrop] {
        try await load(.drops, as: [HiveDrop].self)
    }

    func loadDropDigests() async throws -> [DropDigest] {
        try await load(.dropDigests, as: [DropDigest].self)
    }

    func signOut() async {
        if let credentials {
            try? await client.signOut(credentials)
        }
        try? credentialStore.clear()
        credentials = nil
        user = nil
        server = nil
        phase = .signedOut
    }

    private func load<Value: Decodable>(
        _ resource: HiveResource,
        as type: Value.Type
    ) async throws -> Value {
        guard let credentials else {
            throw MobileClientError("The sign-in session is missing.")
        }
        let result = try await client.resource(resource, session: credentials, as: type)
        try credentialStore.save(result.session)
        self.credentials = result.session
        return result.value
    }
}
