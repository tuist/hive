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

struct HiveErrorIssue: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let culprit: String?
    let level: String
    let status: String
    let platform: String?
    let eventCount: Int
    let firstSeen: String?
    let lastSeen: String?
    let projectId: String?
    let projectName: String?
    let fingerprint: String?
    let dashboardURL: String?
    let environment: String?
    let release: String?
    let exceptionType: String?
    let exceptionValue: String?
    let topFrameFunction: String?
    let topFrameFilename: String?

    enum CodingKeys: String, CodingKey {
        case id, title, culprit, level, status, platform
        case eventCount = "event_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case projectId = "project_id"
        case projectName = "project_name"
        case fingerprint
        case dashboardURL = "dashboard_url"
        case environment, release
        case exceptionType = "exception_type"
        case exceptionValue = "exception_value"
        case topFrameFunction = "top_frame_function"
        case topFrameFilename = "top_frame_filename"
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
