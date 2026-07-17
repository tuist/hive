package dev.tuist.hive

data class OAuthSession(val raw: String)

data class PendingAuthorization(val raw: String)

enum class HiveResource(val wireValue: String) {
    CURRENT_USER("current_user"),
    FORAGE("forage"),
    SPECS("specs"),
    DROPS("drops"),
    DROP_DIGESTS("drop_digests"),
}

object SharedCore {
    init {
        System.loadLibrary("hive_mobile_core")
    }

    fun authorizationStart(
        server: String,
        redirectUri: String,
        state: String,
        verifier: String,
    ): String = unwrap(mobileAuthorizationStart(server, redirectUri, state, verifier))

    fun callbackStart(callbackUrl: String, pending: PendingAuthorization): String =
        unwrap(mobileCallbackStart(callbackUrl, pending.raw))

    fun resourceStart(session: OAuthSession, resource: HiveResource, now: Long): String =
        unwrap(mobileResourceStart(session.raw, resource.wireValue, now.toString()))

    fun continueClient(
        continuation: String,
        response: String,
        status: Int,
        now: Long,
    ): String = unwrap(
        mobileClientContinue(continuation, response, status.toString(), now.toString()),
    )

    fun signOutStart(session: OAuthSession): String = unwrap(mobileSignOutStart(session.raw))

    fun server(session: OAuthSession): String = unwrap(mobileSessionServer(session.raw))

    private fun unwrap(value: String): String {
        return when {
            value.startsWith("ok:") -> value.removePrefix("ok:")
            value.startsWith("error:") -> throw SharedCoreException(value.removePrefix("error:"))
            else -> throw SharedCoreException("The shared core returned an invalid value.")
        }
    }

    @JvmStatic
    private external fun mobileAuthorizationStart(
        server: String,
        redirectUri: String,
        state: String,
        verifier: String,
    ): String

    @JvmStatic
    private external fun mobileCallbackStart(callbackUrl: String, pending: String): String

    @JvmStatic
    private external fun mobileResourceStart(
        session: String,
        resource: String,
        now: String,
    ): String

    @JvmStatic
    private external fun mobileClientContinue(
        continuation: String,
        response: String,
        status: String,
        now: String,
    ): String

    @JvmStatic
    private external fun mobileSignOutStart(session: String): String

    @JvmStatic
    private external fun mobileSessionServer(session: String): String
}

class SharedCoreException(message: String) : Exception(message)
