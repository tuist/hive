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

data class ResourceResult<Value>(val session: OAuthSession, val value: Value)

fun MobileClient.currentUser(session: OAuthSession): ResourceResult<HiveUser> {
    val result = resource(session, HiveResource.CURRENT_USER)
    val data = result.data as? JSONObject ?: throw invalidResource()
    return ResourceResult(
        result.session,
        HiveUser(
            id = data.requiredString("id"),
            email = data.requiredString("email"),
            name = data.nullableString("name"),
            role = data.requiredString("role"),
        ),
    )
}

fun MobileClient.forage(session: OAuthSession): ResourceResult<List<ForageItem>> {
    val result = resource(session, HiveResource.FORAGE)
    val data = result.data as? JSONArray ?: throw invalidResource()
    return ResourceResult(
        result.session,
        data.objects().map { item ->
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
        },
    )
}

fun MobileClient.specs(session: OAuthSession): ResourceResult<List<HiveSpec>> {
    val result = resource(session, HiveResource.SPECS)
    val data = result.data as? JSONArray ?: throw invalidResource()
    return ResourceResult(
        result.session,
        data.objects().map { spec ->
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
        },
    )
}

fun MobileClient.drops(session: OAuthSession): ResourceResult<List<HiveDrop>> {
    val result = resource(session, HiveResource.DROPS)
    val data = result.data as? JSONArray ?: throw invalidResource()
    return ResourceResult(
        result.session,
        data.objects().map { drop ->
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
        },
    )
}

fun MobileClient.dropDigests(session: OAuthSession): ResourceResult<List<DropDigest>> {
    val result = resource(session, HiveResource.DROP_DIGESTS)
    val data = result.data as? JSONArray ?: throw invalidResource()
    return ResourceResult(
        result.session,
        data.objects().map { digest ->
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
        },
    )
}

private fun JSONObject.nullableString(key: String): String? {
    if (isNull(key)) return null
    return optString(key).takeIf { it.isNotBlank() }
}

private fun JSONArray.objects(): List<JSONObject> =
    (0 until length()).map(::getJSONObject)

private fun JSONArray.domains(): List<HiveDomain> =
    objects().map { HiveDomain(it.requiredString("id"), it.requiredString("name")) }

private fun invalidResource() =
    MobileClientException("The shared core returned an invalid resource action.")
