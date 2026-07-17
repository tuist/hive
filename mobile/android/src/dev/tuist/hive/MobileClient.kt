package dev.tuist.hive

import android.util.Base64
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom

data class PreparedAuthorization(
    val url: String,
    val pending: PendingAuthorization,
)

data class RawResourceResult(
    val session: OAuthSession,
    val data: Any,
)

private data class NativeResponse(
    val status: Int,
    val body: String,
)

class MobileClient {
    companion object {
        const val REDIRECT_URI = "dev.tuist.hive://oauth2redirect"
    }

    private val transport = NativeHttpTransport()

    fun prepare(server: String): PreparedAuthorization {
        val effect = run(
            SharedCore.authorizationStart(
                server,
                REDIRECT_URI,
                randomSecret(),
                randomSecret(),
            ),
        )
        if (effect.requiredString("effect") != "browser") {
            throw MobileClientException("The shared core returned an invalid browser action.")
        }
        return PreparedAuthorization(
            url = effect.requiredString("authorization_url"),
            pending = PendingAuthorization(effect.requiredString("pending")),
        )
    }

    fun exchange(callbackUrl: String, pending: PendingAuthorization): OAuthSession {
        val effect = run(SharedCore.callbackStart(callbackUrl, pending))
        if (effect.requiredString("effect") != "session") {
            throw MobileClientException("The shared core returned an invalid session action.")
        }
        return OAuthSession(effect.requiredString("session"))
    }

    fun resource(session: OAuthSession, resource: HiveResource): RawResourceResult {
        val effect = run(SharedCore.resourceStart(session, resource, nowEpochSeconds()))
        if (effect.requiredString("effect") != "resource") {
            throw MobileClientException("The shared core returned an invalid resource action.")
        }
        return RawResourceResult(
            session = OAuthSession(effect.requiredString("session")),
            data = effect.get("data"),
        )
    }

    fun signOut(session: OAuthSession) {
        val effect = run(SharedCore.signOutStart(session))
        if (effect.requiredString("effect") != "done") {
            throw MobileClientException("The shared core returned an invalid sign-out action.")
        }
    }

    fun server(session: OAuthSession): String = SharedCore.server(session)

    private fun run(firstEffect: String): JSONObject {
        var effect = JSONObject(firstEffect)
        while (effect.requiredString("effect") == "http") {
            val response = transport.send(effect.getJSONObject("request"))
            effect = JSONObject(
                SharedCore.continueClient(
                    effect.requiredString("continuation"),
                    response.body,
                    response.status,
                    nowEpochSeconds(),
                ),
            )
        }
        return effect
    }

    private fun randomSecret(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }
}

private class NativeHttpTransport {
    fun send(plan: JSONObject): NativeResponse {
        val connection = URL(plan.requiredString("url")).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = plan.requiredString("method")
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.setRequestProperty("Accept", plan.requiredString("accept"))
            plan.optionalString("authorization")?.let {
                connection.setRequestProperty("Authorization", it)
            }
            plan.optionalString("body")?.let { body ->
                connection.doOutput = true
                connection.setRequestProperty(
                    "Content-Type",
                    plan.requiredString("content_type"),
                )
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }

            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            return NativeResponse(
                status = status,
                body = stream?.bufferedReader()?.use { it.readText() }.orEmpty(),
            )
        } finally {
            connection.disconnect()
        }
    }
}

internal fun JSONObject.requiredString(key: String): String {
    val value = optString(key)
    if (value.isBlank()) {
        throw MobileClientException("Hive returned a response the application could not read.")
    }
    return value
}

internal fun JSONObject.optionalString(key: String): String? {
    if (isNull(key)) return null
    return optString(key).takeIf { it.isNotBlank() }
}

internal fun nowEpochSeconds(): Long = System.currentTimeMillis() / 1_000

class MobileClientException(message: String) : Exception(message)
