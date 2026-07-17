import Foundation

struct HiveUser: Decodable, Equatable {
    let id: String
    let email: String
    let name: String?
    let role: String
}

struct HiveDomain: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct ForageItem: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let status: String
    let visibility: String?
    let sourceLabel: String?
    let externalLabel: String?
    let externalURL: String?
    let occurredAt: String?
    let updatedAt: String
    let domains: [HiveDomain]

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, status, visibility, domains
        case sourceLabel = "source_label"
        case externalLabel = "external_label"
        case externalURL = "external_url"
        case occurredAt = "occurred_at"
        case updatedAt = "updated_at"
    }
}

struct HiveSpec: Decodable, Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let summary: String?
    let body: String
    let status: String
    let visibility: String
    let revision: Int
    let hasNewActivity: Bool
    let updatedAt: String
    let domains: [HiveDomain]

    enum CodingKeys: String, CodingKey {
        case id, number, title, summary, body, status, visibility, revision, domains
        case hasNewActivity = "has_new_activity"
        case updatedAt = "updated_at"
    }
}

struct HiveDrop: Decodable, Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let body: String?
    let sourceType: String
    let version: String?
    let url: String
    let publishedAt: String?
    let domains: [HiveDomain]

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, version, url, domains
        case sourceType = "source_type"
        case publishedAt = "published_at"
    }
}

struct DropDigest: Decodable, Identifiable, Hashable {
    let id: String
    let weekStart: String
    let weekEnd: String
    let title: String
    let summary: String
    let body: String
    let dropCount: Int
    let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, summary, body
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case dropCount = "drop_count"
        case publishedAt = "published_at"
    }
}

private struct ResourceResponse<Resource: Decodable>: Decodable {
    let data: Resource
}

struct HiveAPIClient {
    private let core = SharedCore()
    private let transport = NativeHTTPTransport()

    func currentUser(using credentials: OAuthSession) async throws -> HiveUser {
        let response: ResourceResponse<HiveUser> = try await get("/me", using: credentials)
        return response.data
    }

    func forage(using credentials: OAuthSession) async throws -> [ForageItem] {
        let response: ResourceResponse<[ForageItem]> = try await get(
            "/forage?page_size=100",
            using: credentials
        )
        return response.data
    }

    func specs(using credentials: OAuthSession) async throws -> [HiveSpec] {
        let response: ResourceResponse<[HiveSpec]> = try await get(
            "/specs?page_size=100",
            using: credentials
        )
        return response.data
    }

    func drops(using credentials: OAuthSession) async throws -> [HiveDrop] {
        let response: ResourceResponse<[HiveDrop]> = try await get(
            "/drops?page_size=100",
            using: credentials
        )
        return response.data
    }

    func dropDigests(using credentials: OAuthSession) async throws -> [DropDigest] {
        let response: ResourceResponse<[DropDigest]> = try await get(
            "/drops/digests?page_size=100",
            using: credentials
        )
        return response.data
    }

    private func get<Response: Decodable>(
        _ path: String,
        using credentials: OAuthSession
    ) async throws -> Response {
        do {
            let body = try await transport.send(
                plan: core.apiRequest(session: credentials, path: path)
            )
            return try JSONDecoder().decode(Response.self, from: Data(body.utf8))
        } catch let error as OAuthClientError {
            throw HiveAPIError(message: error.message, statusCode: error.statusCode)
        } catch {
            throw HiveAPIError(message: "Hive returned a response the application could not read.")
        }
    }
}

struct HiveAPIError: LocalizedError {
    let message: String
    var statusCode: Int?

    init(message: String, statusCode: Int? = nil) {
        self.message = message
        self.statusCode = statusCode
    }

    var errorDescription: String? { message }
}
