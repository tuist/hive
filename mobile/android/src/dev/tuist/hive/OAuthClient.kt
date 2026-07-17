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

class OAuthClient {
    companion object {
        const val REDIRECT_URI = "dev.tuist.hive://oauth2redirect"
    }

    private val transport = NativeHttpTransport()

    fun prepare(serverInput: String): PreparedAuthorization {
        val discovery = transport.send(SharedCore.discoveryRequest(serverInput))
        val registration = transport.send(
            SharedCore.registrationRequest(serverInput, discovery, REDIRECT_URI),
        )
        val plan = JSONObject(
            SharedCore.authorizationPlan(
                serverInput,
                discovery,
                registration,
                REDIRECT_URI,
                randomSecret(),
                randomSecret(),
            ),
        )
        return PreparedAuthorization(
            url = plan.requiredString("authorization_url"),
            pending = PendingAuthorization(plan.requiredString("pending")),
        )
    }

    fun exchange(callbackUrl: String, pending: PendingAuthorization): OAuthSession {
        val response = transport.send(SharedCore.tokenRequest(callbackUrl, pending))
        return SharedCore.sessionFromToken(pending, response, nowEpochSeconds())
    }

    fun refresh(session: OAuthSession): OAuthSession {
        val response = transport.send(SharedCore.refreshRequest(session))
        return SharedCore.sessionFromRefresh(session, response, nowEpochSeconds())
    }

    fun revoke(session: OAuthSession) {
        transport.send(SharedCore.revokeRequest(session))
    }

    fun shouldRefresh(session: OAuthSession): Boolean =
        SharedCore.shouldRefresh(session, nowEpochSeconds())

    fun server(session: OAuthSession): String = SharedCore.server(session)

    private fun randomSecret(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }
}

class NativeHttpTransport {
    fun send(rawPlan: String): String {
        val plan = JSONObject(rawPlan)
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
            val response = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                val description = runCatching {
                    JSONObject(response).optionalString("error_description")
                }.getOrNull()
                throw OAuthClientException(
                    description ?: "Hive returned status $status.",
                    status,
                )
            }
            return response
        } finally {
            connection.disconnect()
        }
    }
}

internal fun JSONObject.requiredString(key: String): String {
    val value = optString(key)
    if (value.isBlank()) {
        throw OAuthClientException("Hive returned a response the application could not read.")
    }
    return value
}

internal fun JSONObject.optionalString(key: String): String? {
    if (isNull(key)) return null
    return optString(key).takeIf { it.isNotBlank() }
}

internal fun nowEpochSeconds(): Long = System.currentTimeMillis() / 1_000

class OAuthClientException(message: String, val statusCode: Int? = null) : Exception(message)
