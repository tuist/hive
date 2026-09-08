import Foundation

@_silgen_name("hive_mobile_authorization_start")
private func hiveMobileAuthorizationStart(
    _ server: UnsafePointer<CChar>?,
    _ redirectURI: UnsafePointer<CChar>?,
    _ state: UnsafePointer<CChar>?,
    _ verifier: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_callback_start")
private func hiveMobileCallbackStart(
    _ callbackURL: UnsafePointer<CChar>?,
    _ pending: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_resource_start")
private func hiveMobileResourceStart(
    _ session: UnsafePointer<CChar>?,
    _ resource: UnsafePointer<CChar>?,
    _ now: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_client_continue")
private func hiveMobileClientContinue(
    _ continuation: UnsafePointer<CChar>?,
    _ response: UnsafePointer<CChar>?,
    _ status: UnsafePointer<CChar>?,
    _ now: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_sign_out_start")
private func hiveMobileSignOutStart(
    _ session: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_mobile_session_server")
private func hiveMobileSessionServer(
    _ session: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("hive_string_free")
private func hiveStringFree(_ value: UnsafeMutablePointer<CChar>?)

struct OAuthSession: Codable, Equatable {
    let raw: String
}

struct PendingAuthorization: Equatable {
    let raw: String
}

enum HiveResource: String {
    case currentUser = "current_user"
    case forage
    case specs
    case drops
    case dropDigests = "drop_digests"
}

struct SharedCore {
    func authorizationStart(
        server: String,
        redirectURI: String,
        state: String,
        verifier: String
    ) throws -> String {
        try four(server, redirectURI, state, verifier, hiveMobileAuthorizationStart)
    }

    func callbackStart(callbackURL: String, pending: PendingAuthorization) throws -> String {
        try two(callbackURL, pending.raw, hiveMobileCallbackStart)
    }

    func resourceStart(
        session: OAuthSession,
        resource: HiveResource,
        now: Int64
    ) throws -> String {
        try three(session.raw, resource.rawValue, String(now), hiveMobileResourceStart)
    }

    func continueClient(
        continuation: String,
        response: String,
        status: Int,
        now: Int64
    ) throws -> String {
        try four(
            continuation,
            response,
            String(status),
            String(now),
            hiveMobileClientContinue
        )
    }

    func signOutStart(session: OAuthSession) throws -> String {
        try one(session.raw, hiveMobileSignOutStart)
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

    private func four(
        _ first: String,
        _ second: String,
        _ third: String,
        _ fourth: String,
        _ operation: (
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?
        ) -> UnsafeMutablePointer<CChar>?
    ) throws -> String {
        try first.withCString { first in
            try second.withCString { second in
                try third.withCString { third in
                    try fourth.withCString { fourth in
                        try decode(operation(first, second, third, fourth))
                    }
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
