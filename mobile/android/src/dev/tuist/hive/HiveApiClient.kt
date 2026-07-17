package dev.tuist.hive

import org.json.JSONArray
import org.json.JSONObject

data class HiveUser(
    val id: String,
    val email: String,
    val name: String?,
    val role: String,
)

data class HiveDomain(val id: String, val name: String)

data class ForageItem(
    val id: String,
    val type: String,
    val title: String,
    val body: String?,
    val status: String,
    val visibility: String?,
    val sourceLabel: String?,
    val externalLabel: String?,
    val externalUrl: String?,
    val domains: List<HiveDomain>,
)

data class HiveSpec(
    val id: String,
    val number: Int,
    val title: String,
    val summary: String?,
    val body: String,
    val status: String,
    val visibility: String,
    val revision: Int,
    val hasNewActivity: Boolean,
    val domains: List<HiveDomain>,
)

data class HiveDrop(
    val id: String,
    val number: Int,
    val title: String,
    val body: String?,
    val sourceType: String,
    val version: String?,
    val url: String,
    val publishedAt: String?,
    val domains: List<HiveDomain>,
)

data class DropDigest(
    val id: String,
    val weekStart: String,
    val weekEnd: String,
    val title: String,
    val summary: String,
    val body: String,
    val dropCount: Int,
    val publishedAt: String,
)

class HiveApiClient {
    private val transport = NativeHttpTransport()

    fun currentUser(session: OAuthSession): HiveUser {
        val data = get(session, "/me").getJSONObject("data")
        return HiveUser(
            id = data.requiredString("id"),
            email = data.requiredString("email"),
            name = data.nullableString("name"),
            role = data.requiredString("role"),
        )
    }

    fun forage(session: OAuthSession): List<ForageItem> {
        val data = get(session, "/forage?page_size=100").getJSONArray("data")
        return data.objects().map { item ->
            ForageItem(
                id = item.requiredString("id"),
                type = item.requiredString("type"),
                title = item.requiredString("title"),
                body = item.nullableString("body"),
                status = item.requiredString("status"),
                visibility = item.nullableString("visibility"),
                sourceLabel = item.nullableString("source_label"),
                externalLabel = item.nullableString("external_label"),
                externalUrl = item.nullableString("external_url"),
                domains = item.getJSONArray("domains").domains(),
            )
        }
    }

    fun specs(session: OAuthSession): List<HiveSpec> {
        val data = get(session, "/specs?page_size=100").getJSONArray("data")
        return data.objects().map { spec ->
            HiveSpec(
                id = spec.requiredString("id"),
                number = spec.getInt("number"),
                title = spec.requiredString("title"),
                summary = spec.nullableString("summary"),
                body = spec.requiredString("body"),
                status = spec.requiredString("status"),
                visibility = spec.requiredString("visibility"),
                revision = spec.getInt("revision"),
                hasNewActivity = spec.optBoolean("has_new_activity"),
                domains = spec.getJSONArray("domains").domains(),
            )
        }
    }

    fun drops(session: OAuthSession): List<HiveDrop> {
        val data = get(session, "/drops?page_size=100").getJSONArray("data")
        return data.objects().map { drop ->
            HiveDrop(
                id = drop.requiredString("id"),
                number = drop.getInt("number"),
                title = drop.requiredString("title"),
                body = drop.nullableString("body"),
                sourceType = drop.requiredString("source_type"),
                version = drop.nullableString("version"),
                url = drop.requiredString("url"),
                publishedAt = drop.nullableString("published_at"),
                domains = drop.getJSONArray("domains").domains(),
            )
        }
    }

    fun dropDigests(session: OAuthSession): List<DropDigest> {
        val data = get(session, "/drops/digests?page_size=100").getJSONArray("data")
        return data.objects().map { digest ->
            DropDigest(
                id = digest.requiredString("id"),
                weekStart = digest.requiredString("week_start"),
                weekEnd = digest.requiredString("week_end"),
                title = digest.requiredString("title"),
                summary = digest.requiredString("summary"),
                body = digest.requiredString("body"),
                dropCount = digest.getInt("drop_count"),
                publishedAt = digest.requiredString("published_at"),
            )
        }
    }

    private fun get(session: OAuthSession, path: String): JSONObject {
        try {
            return JSONObject(transport.send(SharedCore.apiRequest(session, path)))
        } catch (error: OAuthClientException) {
            throw HiveApiException(error.message ?: "Hive request failed.", error.statusCode)
        }
    }
}

private fun JSONObject.nullableString(key: String): String? {
    if (isNull(key)) return null
    return optString(key).takeIf { it.isNotBlank() }
}

private fun JSONArray.objects(): List<JSONObject> =
    (0 until length()).map(::getJSONObject)

private fun JSONArray.domains(): List<HiveDomain> =
    objects().map { HiveDomain(it.requiredString("id"), it.requiredString("name")) }

class HiveApiException(message: String, val statusCode: Int? = null) : Exception(message)
