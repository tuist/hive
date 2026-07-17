import Foundation

@_silgen_name("hive_mobile_discovery_request")
private func hiveMobileDiscoveryRequest(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_registration_request")
private func hiveMobileRegistrationRequest(
    _ server: UnsafePointer<CChar>?,
    _ discovery: UnsafePointer<CChar>?,
    _ redirectURI: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_authorization_plan")
private func hiveMobileAuthorizationPlan(
    _ server: UnsafePointer<CChar>?,
    _ discovery: UnsafePointer<CChar>?,
    _ registration: UnsafePointer<CChar>?,
    _ redirectURI: UnsafePointer<CChar>?,
    _ state: UnsafePointer<CChar>?,
    _ verifier: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_token_request")
private func hiveMobileTokenRequest(
    _ callbackURL: UnsafePointer<CChar>?,
    _ pending: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_session_from_token")
private func hiveMobileSessionFromToken(
    _ pending: UnsafePointer<CChar>?,
    _ response: UnsafePointer<CChar>?,
    _ now: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_refresh_request")
private func hiveMobileRefreshRequest(_ session: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_session_from_refresh")
private func hiveMobileSessionFromRefresh(
    _ session: UnsafePointer<CChar>?,
    _ response: UnsafePointer<CChar>?,
    _ now: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_revoke_request")
private func hiveMobileRevokeRequest(_ session: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_api_request")
private func hiveMobileAPIRequest(
    _ session: UnsafePointer<CChar>?,
    _ path: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_session_should_refresh")
private func hiveMobileSessionShouldRefresh(
    _ session: UnsafePointer<CChar>?,
    _ now: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_session_server")
private func hiveMobileSessionServer(_ session: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_string_free")
private func hiveStringFree(_ value: UnsafeMutablePointer<CChar>?)

struct OAuthSession: Codable, Equatable {
    let raw: String
}

struct PendingAuthorization: Equatable {
    let raw: String
}

struct SharedCore {
    func discoveryRequest(serverInput: String) throws -> String {
        try one(serverInput, hiveMobileDiscoveryRequest)
    }

    func registrationRequest(
        serverInput: String,
        discoveryResponse: String,
        redirectURI: String
    ) throws -> String {
        try three(serverInput, discoveryResponse, redirectURI, hiveMobileRegistrationRequest)
    }

    func authorizationPlan(
        serverInput: String,
        discoveryResponse: String,
        registrationResponse: String,
        redirectURI: String,
        state: String,
        verifier: String
    ) throws -> String {
        try serverInput.withCString { server in
            try discoveryResponse.withCString { discovery in
                try registrationResponse.withCString { registration in
                    try redirectURI.withCString { redirect in
                        try state.withCString { state in
                            try verifier.withCString { verifier in
                                try decode(
                                    hiveMobileAuthorizationPlan(
                                        server,
                                        discovery,
                                        registration,
                                        redirect,
                                        state,
                                        verifier
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func tokenRequest(callbackURL: String, pending: PendingAuthorization) throws -> String {
        try two(callbackURL, pending.raw, hiveMobileTokenRequest)
    }

    func sessionFromToken(
        pending: PendingAuthorization,
        response: String,
        now: Int64
    ) throws -> OAuthSession {
        OAuthSession(raw: try three(pending.raw, response, String(now), hiveMobileSessionFromToken))
    }

    func refreshRequest(session: OAuthSession) throws -> String {
        try one(session.raw, hiveMobileRefreshRequest)
    }

    func sessionFromRefresh(
        session: OAuthSession,
        response: String,
        now: Int64
    ) throws -> OAuthSession {
        OAuthSession(raw: try three(session.raw, response, String(now), hiveMobileSessionFromRefresh))
    }

    func revokeRequest(session: OAuthSession) throws -> String {
        try one(session.raw, hiveMobileRevokeRequest)
    }

    func apiRequest(session: OAuthSession, path: String) throws -> String {
        try two(session.raw, path, hiveMobileAPIRequest)
    }

    func shouldRefresh(session: OAuthSession, now: Int64) throws -> Bool {
        try two(session.raw, String(now), hiveMobileSessionShouldRefresh) == "true"
    }

    func server(session: OAuthSession) throws -> String {
        try one(session.raw, hiveMobileSessionServer)
    }

    private func one(
        _ value: String,
        _ operation: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    ) throws -> String {
        try value.withCString { try decode(operation($0)) }
    }

    private func two(
        _ first: String,
        _ second: String,
        _ operation: (
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?
        ) -> UnsafeMutablePointer<CChar>?
    ) throws -> String {
        try first.withCString { first in
            try second.withCString { second in
                try decode(operation(first, second))
            }
        }
    }

    private func three(
        _ first: String,
        _ second: String,
        _ third: String,
        _ operation: (
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?
        ) -> UnsafeMutablePointer<CChar>?
    ) throws -> String {
        try first.withCString { first in
            try second.withCString { second in
                try third.withCString { third in
                    try decode(operation(first, second, third))
                }
            }
        }
    }

    private func decode(_ raw: UnsafeMutablePointer<CChar>?) throws -> String {
        guard let raw else {
            throw SharedCoreError("The shared core did not return a value.")
        }
        defer { hiveStringFree(raw) }

        let value = String(cString: raw)
        if value.hasPrefix("ok:") {
            return String(value.dropFirst(3))
        }
        if value.hasPrefix("error:") {
            throw SharedCoreError(String(value.dropFirst(6)))
        }
        throw SharedCoreError("The shared core returned an invalid value.")
    }
}

struct SharedCoreError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
