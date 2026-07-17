import Foundation
import Security

struct PreparedAuthorization {
    let url: URL
    let pending: PendingAuthorization
}

struct ResourceResult<Value> {
    let session: OAuthSession
    let value: Value
}

private struct NativeRequestPlan: Decodable {
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

private struct EffectHeader: Decodable {
    let effect: String
}

private struct HTTPEffect: Decodable {
    let effect: String
    let request: NativeRequestPlan
    let continuation: String
}

private struct BrowserEffect: Decodable {
    let effect: String
    let authorizationURL: String
    let pending: String

    enum CodingKeys: String, CodingKey {
        case effect, pending
        case authorizationURL = "authorization_url"
    }
}

private struct SessionEffect: Decodable {
    let effect: String
    let session: String
}

private struct ResourceEffect<Value: Decodable>: Decodable {
    let effect: String
    let session: String
    let data: Value
}

private struct NativeResponse {
    let status: Int
    let body: String
}

struct MobileClient {
    static let redirectURI = "dev.tuist.hive://oauth2redirect"

    private let core = SharedCore()
    private let transport = NativeHTTPTransport()

    func prepare(server: String) async throws -> PreparedAuthorization {
        let effect = try core.authorizationStart(
            server: server,
            redirectURI: Self.redirectURI,
            state: try randomSecret(),
            verifier: try randomSecret()
        )
        let final = try await run(effect)
        let browser: BrowserEffect = try decode(final)
        guard browser.effect == "browser", let url = URL(string: browser.authorizationURL) else {
            throw MobileClientError("The shared core returned an invalid browser action.")
        }
        return PreparedAuthorization(
            url: url,
            pending: PendingAuthorization(raw: browser.pending)
        )
    }

    func exchange(callbackURL: URL, pending: PendingAuthorization) async throws -> OAuthSession {
        let final = try await run(
            core.callbackStart(callbackURL: callbackURL.absoluteString, pending: pending)
        )
        let session: SessionEffect = try decode(final)
        guard session.effect == "session" else {
            throw MobileClientError("The shared core returned an invalid session action.")
        }
        return OAuthSession(raw: session.session)
    }

    func resource<Value: Decodable>(
        _ resource: HiveResource,
        session: OAuthSession,
        as _: Value.Type = Value.self
    ) async throws -> ResourceResult<Value> {
        let final = try await run(
            core.resourceStart(session: session, resource: resource, now: nowEpochSeconds())
        )
        let result: ResourceEffect<Value> = try decode(final)
        guard result.effect == "resource" else {
            throw MobileClientError("The shared core returned an invalid resource action.")
        }
        return ResourceResult(session: OAuthSession(raw: result.session), value: result.data)
    }

    func signOut(_ session: OAuthSession) async throws {
        let final = try await run(core.signOutStart(session: session))
        let result: EffectHeader = try decode(final)
        guard result.effect == "done" else {
            throw MobileClientError("The shared core returned an invalid sign-out action.")
        }
    }

    func server(_ session: OAuthSession) throws -> String {
        try core.server(session: session)
    }

    private func run(_ firstEffect: String) async throws -> String {
        var effect = firstEffect
        while true {
            let header: EffectHeader = try decode(effect)
            guard header.effect == "http" else { return effect }
            let request: HTTPEffect = try decode(effect)
            let response = try await transport.send(plan: request.request)
            effect = try core.continueClient(
                continuation: request.continuation,
                response: response.body,
                status: response.status,
                now: nowEpochSeconds()
            )
        }
    }

    private func randomSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw MobileClientError("The application could not create a secure sign-in session.")
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct NativeHTTPTransport {
    private let session = URLSession.shared

    func send(plan: NativeRequestPlan) async throws -> NativeResponse {
        guard let url = URL(string: plan.url) else {
            throw MobileClientError("The shared core returned an invalid endpoint address.")
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
        guard let response = response as? HTTPURLResponse,
              let body = String(data: data, encoding: .utf8)
        else {
            throw MobileClientError("Hive returned a response the application could not read.")
        }
        return NativeResponse(status: response.statusCode, body: body)
    }
}

private func decode<Value: Decodable>(_ value: String) throws -> Value {
    do {
        return try JSONDecoder().decode(Value.self, from: Data(value.utf8))
    } catch {
        throw MobileClientError("The shared core returned an invalid action.")
    }
}

private func nowEpochSeconds() -> Int64 {
    Int64(Date().timeIntervalSince1970)
}

struct MobileClientError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
