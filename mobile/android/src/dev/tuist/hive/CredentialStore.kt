package dev.tuist.hive

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class CredentialStore(context: Context) {
    private val preferences = context.getSharedPreferences("hive_oauth", Context.MODE_PRIVATE)
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun load(): OAuthSession? {
        val encoded = preferences.getString(SESSION_KEY, null) ?: return null
        val payload = Base64.decode(encoded, Base64.NO_WRAP)
        if (payload.size <= IV_LENGTH) throw CredentialStoreException("The saved session is invalid.")

        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(createIfMissing = false),
            GCMParameterSpec(128, payload.copyOfRange(0, IV_LENGTH)),
        )
        val cleartext = cipher.doFinal(payload.copyOfRange(IV_LENGTH, payload.size))
        return OAuthSession(String(cleartext, Charsets.UTF_8))
    }

    fun save(session: OAuthSession) {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey(createIfMissing = true))
        val encrypted = cipher.doFinal(session.raw.toByteArray(Charsets.UTF_8))
        val payload = cipher.iv + encrypted
        preferences.edit()
            .putString(SESSION_KEY, Base64.encodeToString(payload, Base64.NO_WRAP))
            .apply()
    }

    fun clear() {
        preferences.edit().remove(SESSION_KEY).apply()
    }

    private fun secretKey(createIfMissing: Boolean): SecretKey {
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing
        if (!createIfMissing) throw CredentialStoreException("The secure session key is missing.")

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        private const val KEY_ALIAS = "dev.tuist.hive.oauth"
        private const val SESSION_KEY = "session"
        private const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH = 12
    }
}

class CredentialStoreException(message: String) : Exception(message)
