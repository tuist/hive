import Foundation
import Security

struct PreparedAuthorization {
    let url: URL
    let pending: PendingAuthorization
}

struct NativeRequestPlan: Decodable {
    let method: String
    let url: String
    let accept: String
    let body: String?
    let contentType: String?
    let authorization: String?

    enum CodingKeys: String, CodingKey {
        case method, url, accept, body, authorization
        case contentType = "content_type"
    }
}

struct AuthorizationPlan: Decodable {
    let authorizationURL: String
    let pending: String

    enum CodingKeys: String, CodingKey {
        case authorizationURL = "authorization_url"
        case pending
    }
}

struct OAuthClient {
    static let redirectURI = "dev.tuist.hive://oauth2redirect"

    private let core = SharedCore()
    private let transport = NativeHTTPTransport()

    func prepare(serverInput: String) async throws -> PreparedAuthorization {
        let discovery = try await transport.send(
            plan: core.discoveryRequest(serverInput: serverInput)
        )
        let registration = try await transport.send(
            plan: core.registrationRequest(
                serverInput: serverInput,
                discoveryResponse: discovery,
                redirectURI: Self.redirectURI
            )
        )
        let rawPlan = try core.authorizationPlan(
            serverInput: serverInput,
            discoveryResponse: discovery,
            registrationResponse: registration,
            redirectURI: Self.redirectURI,
            state: try randomSecret(),
            verifier: try randomSecret()
        )
        let plan: AuthorizationPlan = try decode(rawPlan)
        guard let url = URL(string: plan.authorizationURL) else {
            throw OAuthClientError("Hive returned an invalid authorization address.")
        }
        return PreparedAuthorization(
            url: url,
            pending: PendingAuthorization(raw: plan.pending)
        )
    }

    func exchange(callbackURL: URL, pending: PendingAuthorization) async throws -> OAuthSession {
        let response = try await transport.send(
            plan: core.tokenRequest(callbackURL: callbackURL.absoluteString, pending: pending)
        )
        return try core.sessionFromToken(
            pending: pending,
            response: response,
            now: nowEpochSeconds()
        )
    }

    func refresh(_ session: OAuthSession) async throws -> OAuthSession {
        let response = try await transport.send(plan: core.refreshRequest(session: session))
        return try core.sessionFromRefresh(
            session: session,
            response: response,
            now: nowEpochSeconds()
        )
    }

    func revoke(_ session: OAuthSession) async throws {
        _ = try await transport.send(plan: core.revokeRequest(session: session))
    }

    func shouldRefresh(_ session: OAuthSession) throws -> Bool {
        try core.shouldRefresh(session: session, now: nowEpochSeconds())
    }

    func server(_ session: OAuthSession) throws -> String {
        try core.server(session: session)
    }

    private func randomSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw OAuthClientError("The application could not create a secure sign-in session.")
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct NativeHTTPTransport {
    private let session = URLSession.shared

    func send(plan rawPlan: String) async throws -> String {
        let plan: NativeRequestPlan = try decode(rawPlan)
        guard let url = URL(string: plan.url) else {
            throw OAuthClientError("Hive returned an invalid endpoint address.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = plan.method
        request.setValue(plan.accept, forHTTPHeaderField: "Accept")
        if let authorization = plan.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        if let body = plan.body {
            request.httpBody = Data(body.utf8)
            request.setValue(plan.contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OAuthClientError("Hive did not return a valid response.")
        }
        guard 200..<300 ~= response.statusCode else {
            let serverError = try? JSONDecoder().decode(ServerError.self, from: data)
            throw OAuthClientError(
                serverError?.errorDescription ?? "Hive returned status \(response.statusCode).",
                statusCode: response.statusCode
            )
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw OAuthClientError("Hive returned a response the application could not read.")
        }
        return body
    }
}

private struct ServerError: Decodable {
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case errorDescription = "error_description"
    }
}

private func decode<Value: Decodable>(_ value: String) throws -> Value {
    do {
        return try JSONDecoder().decode(Value.self, from: Data(value.utf8))
    } catch {
        throw OAuthClientError("The shared core returned an invalid request plan.")
    }
}

private func nowEpochSeconds() -> Int64 {
    Int64(Date().timeIntervalSince1970)
}

struct OAuthClientError: LocalizedError {
    let message: String
    let statusCode: Int?

    init(_ message: String, statusCode: Int? = nil) {
        self.message = message
        self.statusCode = statusCode
    }

    var errorDescription: String? { message }
}
