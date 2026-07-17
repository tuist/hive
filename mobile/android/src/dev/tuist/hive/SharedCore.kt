package dev.tuist.hive

data class OAuthSession(val raw: String)

data class PendingAuthorization(val raw: String)

object SharedCore {
    init {
        System.loadLibrary("hive_mobile_core")
    }

    fun discoveryRequest(serverInput: String): String = unwrap(mobileDiscoveryRequest(serverInput))

    fun registrationRequest(
        serverInput: String,
        discoveryResponse: String,
        redirectUri: String,
    ): String = unwrap(mobileRegistrationRequest(serverInput, discoveryResponse, redirectUri))

    fun authorizationPlan(
        serverInput: String,
        discoveryResponse: String,
        registrationResponse: String,
        redirectUri: String,
        state: String,
        verifier: String,
    ): String = unwrap(
        mobileAuthorizationPlan(
            serverInput,
            discoveryResponse,
            registrationResponse,
            redirectUri,
            state,
            verifier,
        ),
    )

    fun tokenRequest(callbackUrl: String, pending: PendingAuthorization): String =
        unwrap(mobileTokenRequest(callbackUrl, pending.raw))

    fun sessionFromToken(
        pending: PendingAuthorization,
        response: String,
        now: Long,
    ): OAuthSession = OAuthSession(
        unwrap(mobileSessionFromToken(pending.raw, response, now.toString())),
    )

    fun refreshRequest(session: OAuthSession): String =
        unwrap(mobileRefreshRequest(session.raw))

    fun sessionFromRefresh(
        session: OAuthSession,
        response: String,
        now: Long,
    ): OAuthSession = OAuthSession(
        unwrap(mobileSessionFromRefresh(session.raw, response, now.toString())),
    )

    fun revokeRequest(session: OAuthSession): String = unwrap(mobileRevokeRequest(session.raw))

    fun apiRequest(session: OAuthSession, path: String): String =
        unwrap(mobileApiRequest(session.raw, path))

    fun shouldRefresh(session: OAuthSession, now: Long): Boolean =
        unwrap(mobileSessionShouldRefresh(session.raw, now.toString())) == "true"

    fun server(session: OAuthSession): String = unwrap(mobileSessionServer(session.raw))

    private fun unwrap(value: String): String {
        return when {
            value.startsWith("ok:") -> value.removePrefix("ok:")
            value.startsWith("error:") -> throw SharedCoreException(value.removePrefix("error:"))
            else -> throw SharedCoreException("The shared core returned an invalid value.")
        }
    }

    @JvmStatic
    private external fun mobileDiscoveryRequest(serverInput: String): String

    @JvmStatic
    private external fun mobileRegistrationRequest(
        serverInput: String,
        discoveryResponse: String,
        redirectUri: String,
    ): String

    @JvmStatic
    private external fun mobileAuthorizationPlan(
        serverInput: String,
        discoveryResponse: String,
        registrationResponse: String,
        redirectUri: String,
        state: String,
        verifier: String,
    ): String

    @JvmStatic
    private external fun mobileTokenRequest(callbackUrl: String, pending: String): String

    @JvmStatic
    private external fun mobileSessionFromToken(
        pending: String,
        response: String,
        now: String,
    ): String

    @JvmStatic
    private external fun mobileRefreshRequest(session: String): String

    @JvmStatic
    private external fun mobileSessionFromRefresh(
        session: String,
        response: String,
        now: String,
    ): String

    @JvmStatic
    private external fun mobileRevokeRequest(session: String): String

    @JvmStatic
    private external fun mobileApiRequest(session: String, path: String): String

    @JvmStatic
    private external fun mobileSessionShouldRefresh(session: String, now: String): String

    @JvmStatic
    private external fun mobileSessionServer(session: String): String
}

class SharedCoreException(message: String) : Exception(message)
