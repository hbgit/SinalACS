package br.com.prismrr.sinalacs.acs

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

/**
 * Cofre do refresh token (envelope): RSA-2048/OAEP no Android Keystore com
 * autenticação do usuário exigida a CADA decifra (CryptoObject) protege uma
 * chave AES-256-GCM descartável que cifra o token. Cifrar usa a chave pública e
 * não pede prompt. Só o texto cifrado fica em SharedPreferences privado: sem a
 * chave do TEE ele não vale nada. Nunca registre token, chave ou exceção.
 *
 * Falha fechada: blob corrompido, truncado ou com tag GCM adulterada nunca vai
 * decifrar — é apagado (com a chave) e responde `invalidated`, como a chave
 * invalidada; qualquer outro erro inesperado vira `unavailable`, sem mensagem.
 */
class KeystoreVault(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "br.com.prismrr.sinalacs.acs/keystore_vault"
        private const val PROVIDER = "AndroidKeyStore"
        private const val PREFS = "sinalacs_keystore_vault"
        private const val TRANSFORMATION = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding"
        private const val AES = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
        private const val GCM_IV_BYTES = 12
        private const val AES_KEY_BYTES = 32
        // O provedor do Keystore usa MGF1 com SHA-1 mesmo pedindo SHA-256; os
        // dois lados (cifra fora do Keystore e decifra dentro) usam esta spec.
        private val OAEP = OAEPParameterSpec(
            "SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT,
        )
    }

    /** Responde ao canal uma única vez; respostas tardias são descartadas. */
    private class OnceResult(private val inner: MethodChannel.Result) : MethodChannel.Result {
        private val done = AtomicBoolean(false)
        override fun success(value: Any?) {
            if (done.compareAndSet(false, true)) inner.success(value)
        }
        override fun error(code: String, message: String?, details: Any?) {
            if (done.compareAndSet(false, true)) inner.error(code, message, details)
        }
        override fun notImplemented() {
            if (done.compareAndSet(false, true)) inner.notImplemented()
        }
    }

    /** Blob já validado no formato: IV(12) . chaveAES cifrada com RSA . token cifrado. */
    private class Envelope(val iv: ByteArray, val wrappedKey: ByteArray, val body: ByteArray)

    private val authenticators: Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            // Antes da API 30 o CryptoObject só aceita biometria forte.
            BiometricManager.Authenticators.BIOMETRIC_STRONG
        }

    private val prefs get() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun keyAlias(alias: String) = "sinalacs.vault.$alias"
    private fun keyStore() = KeyStore.getInstance(PROVIDER).apply { load(null) }

    // Chamado na thread da plataforma (principal). seal/delete/contains rodam
    // aqui mesmo; unseal abre o BiometricPrompt nesta thread e responde depois,
    // pelo callback, também na principal (executor do ContextCompat).
    override fun onMethodCall(call: MethodCall, raw: MethodChannel.Result) {
        val result = OnceResult(raw)
        try {
            val alias = call.argument<String>("alias")
            when (call.method) {
                "isSupported" -> result.success(
                    BiometricManager.from(activity).canAuthenticate(authenticators) ==
                        BiometricManager.BIOMETRIC_SUCCESS,
                )
                "contains" -> result.success(alias != null && prefs.contains(alias))
                "seal" -> {
                    seal(alias!!, call.argument<String>("plaintext")!!)
                    result.success(null)
                }
                "unseal" -> unseal(alias!!, call.argument<String>("reason") ?: "", result)
                "delete" -> {
                    delete(alias!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // Sem getMessage: o texto do Keystore não vai para o canal nem para log.
            result.error("unavailable", null, null)
        }
    }

    private fun generateKey(alias: String) {
        val builder = KeyGenParameterSpec.Builder(
            keyAlias(alias),
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(2048)
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0, // a cada uso
                KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
            )
        }
        // Antes da API 30 o padrão (validade -1) já é "a cada uso, só biometria".
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, PROVIDER).run {
            initialize(builder.build())
            generateKeyPair()
        }
    }

    /**
     * Chave privada utilizável, ou `null` se ausente. Lança
     * [KeyPermanentlyInvalidatedException] quando uma biometria nova (ou a
     * remoção do bloqueio de tela) invalidou a chave. `init` não pede
     * autenticação: ela é cobrada no `doFinal`, via CryptoObject.
     */
    private fun initDecrypt(alias: String): Cipher? {
        val key = keyStore().getKey(keyAlias(alias), null) as? PrivateKey ?: return null
        return Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.DECRYPT_MODE, key, OAEP) }
    }

    private fun publicKey(alias: String): PublicKey {
        // Nunca selar um token novo sob uma chave já invalidada: ele nasceria
        // ilegível. Se a privada morreu (ou sumiu), recria o par.
        val usable = try {
            initDecrypt(alias) != null
        } catch (e: KeyPermanentlyInvalidatedException) {
            false
        }
        val ks = keyStore()
        if (!usable) {
            if (ks.containsAlias(keyAlias(alias))) ks.deleteEntry(keyAlias(alias))
            generateKey(alias)
        }
        val pub = keyStore().getCertificate(keyAlias(alias)).publicKey
        // Recria a chave fora do Keystore: a original herda as restrições de
        // autenticação e falharia ao cifrar sem prompt em alguns aparelhos.
        return KeyFactory.getInstance(pub.algorithm).generatePublic(X509EncodedKeySpec(pub.encoded))
    }

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)
    private fun unb64(s: String) = Base64.decode(s, Base64.NO_WRAP)

    /**
     * Envelope: AES-256-GCM descartável cifra o token; a chave AES (32 bytes)
     * é cifrada com a pública RSA. Blob: IV.chaveAES_RSA.token_AES (Base64).
     */
    private fun seal(alias: String, plaintext: String) {
        val aesKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val aes = Cipher.getInstance(AES).apply { init(Cipher.ENCRYPT_MODE, aesKey) }
        val body = aes.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val rsa = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, publicKey(alias), OAEP)
        }
        val wrapped = rsa.doFinal(aesKey.encoded)
        // `commit` (síncrono): o blob novo tem de estar em disco antes do legado
        // ser apagado. Se não gravou, falha (o Dart recebe `unavailable`).
        val ok = prefs.edit().putString(alias, b64(aes.iv) + "." + b64(wrapped) + "." + b64(body)).commit()
        check(ok)
    }

    private fun delete(alias: String) {
        prefs.edit().remove(alias).commit()
        val ks = keyStore()
        if (ks.containsAlias(keyAlias(alias))) ks.deleteEntry(keyAlias(alias))
    }

    /** Valida o formato ANTES do prompt: blob truncado não abre biometria à toa. */
    private fun parse(blob: String): Envelope? = try {
        val parts = blob.split(".")
        if (parts.size != 3) {
            null
        } else {
            val env = Envelope(unb64(parts[0]), unb64(parts[1]), unb64(parts[2]))
            // Corpo menor que a tag GCM não pode ser um token cifrado.
            if (env.iv.size != GCM_IV_BYTES || env.wrappedKey.isEmpty() ||
                env.body.size < GCM_TAG_BITS / 8
            ) null else env
        }
    } catch (e: IllegalArgumentException) {
        null
    }

    private fun unseal(alias: String, reason: String, result: MethodChannel.Result) {
        val blob = prefs.getString(alias, null)
        if (blob == null) {
            result.success(null)
            return
        }
        val envelope = parse(blob)
        if (envelope == null) {
            // Corrompido ou truncado: nunca decifrará. Apaga para não prender o
            // ACS num "indisponível" eterno; o Dart cai no login completo.
            delete(alias)
            result.error("invalidated", null, null)
            return
        }
        val cipher: Cipher
        try {
            val c = initDecrypt(alias)
            if (c == null) {
                // Blob sem chave (ex.: Keystore limpo): nunca decifrará.
                delete(alias)
                result.error("invalidated", null, null)
                return
            }
            cipher = c
        } catch (e: KeyPermanentlyInvalidatedException) {
            delete(alias)
            result.error("invalidated", null, null)
            return
        } catch (e: Exception) {
            result.error("unavailable", null, null)
            return
        }

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("SinalACS")
            .setSubtitle(reason)
            .setAllowedAuthenticators(authenticators)
            .apply {
                // Com DEVICE_CREDENTIAL o botão negativo é proibido.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) setNegativeButtonText("Cancelar")
            }
            .build()

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                var aesBytes: ByteArray? = null
                try {
                    // O CryptoObject é o RSA privado: libera a chave AES, que decifra o token.
                    val rsa = r.cryptoObject?.cipher ?: throw IllegalStateException()
                    aesBytes = rsa.doFinal(envelope.wrappedKey)
                    if (aesBytes.size != AES_KEY_BYTES) throw IllegalStateException()
                    val aes = Cipher.getInstance(AES).apply {
                        init(
                            Cipher.DECRYPT_MODE,
                            SecretKeySpec(aesBytes, "AES"),
                            GCMParameterSpec(GCM_TAG_BITS, envelope.iv),
                        )
                    }
                    // GCM só devolve bytes depois de validar a tag: adulterado
                    // lança AEADBadTagException e nunca sai token parcial.
                    result.success(String(aes.doFinal(envelope.body), Charsets.UTF_8))
                } catch (e: AEADBadTagException) {
                    // Tag GCM não confere: blob adulterado ou corrompido.
                    discard(alias, result)
                } catch (e: Exception) {
                    result.error("unavailable", null, null)
                } finally {
                    aesBytes?.fill(0)
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val mapped = when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> "cancelled"
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockedOut"
                    else -> "unavailable"
                }
                result.error(mapped, null, null)
            }
            // onAuthenticationFailed (digital errada) não encerra: o prompt segue.
        }

        // BiometricPrompt exige a thread principal; onMethodCall já roda nela,
        // e runOnUiThread executa na hora nesse caso. Uma falha ao abrir o
        // prompt responde uma vez só.
        activity.runOnUiThread {
            // Com o estado do FragmentManager já salvo (activity indo para o
            // fundo), a biometric 1.1.0 NÃO lança: registra e retorna em
            // silêncio, sem callback nenhum — o Dart esperaria para sempre.
            if (activity.supportFragmentManager.isStateSaved) {
                result.error("cancelled", null, null)
                return@runOnUiThread
            }
            try {
                BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
                    .authenticate(info, BiometricPrompt.CryptoObject(cipher))
            } catch (e: Exception) {
                result.error("unavailable", null, null)
            }
        }
    }

    /** Apaga blob e chave de um envelope que nunca decifrará e responde `invalidated`. */
    private fun discard(alias: String, result: MethodChannel.Result) {
        try {
            delete(alias)
            result.error("invalidated", null, null)
        } catch (e: Exception) {
            result.error("unavailable", null, null)
        }
    }
}
