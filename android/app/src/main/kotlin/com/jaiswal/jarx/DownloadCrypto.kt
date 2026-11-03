package com.jaiswal.jarx

import android.content.Context
import java.io.File
import java.io.IOException
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

// Encrypts downloaded songs so only JARX can play them (AES-256-CTR with a
// key kept in the app's private storage). File layout: MAGIC, 16-byte IV,
// then the encrypted audio.
//
// ponytail: the key is a private file, not wrapped by the Android Keystore;
// it stops copying and sharing, not someone with root access. Wrap it with a
// Keystore key if that ever matters.
object DownloadCrypto {
    private val MAGIC = "JARXENC1".toByteArray()

    private fun key(context: Context): SecretKeySpec {
        val file = File(context.filesDir, "download.key")
        synchronized(this) {
            if (!file.exists()) {
                val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
                val tmp = File(context.filesDir, "download.key.tmp")
                tmp.writeBytes(bytes)
                if (!tmp.renameTo(file)) throw IOException("could not save the download key")
            }
            return SecretKeySpec(file.readBytes(), "AES")
        }
    }

    private fun cipher(context: Context, mode: Int, iv: ByteArray) =
        Cipher.getInstance("AES/CTR/NoPadding").apply {
            init(mode, key(context), IvParameterSpec(iv))
        }

    /** Writes [src] encrypted to [dst] (via a temp file, so [dst] is never half-written). */
    fun encrypt(context: Context, src: String, dst: String) {
        val iv = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val tmp = File("$dst.part")
        tmp.outputStream().use { out ->
            out.write(MAGIC)
            out.write(iv)
            CipherInputStream(File(src).inputStream(), cipher(context, Cipher.ENCRYPT_MODE, iv))
                .use { it.copyTo(out, 1 shl 16) }
        }
        if (!tmp.renameTo(File(dst))) throw IOException("could not write $dst")
    }

    /** Writes the playable audio of [src] (made by [encrypt]) to [dst]. */
    fun decrypt(context: Context, src: String, dst: String) {
        File(src).inputStream().use { input ->
            val magic = ByteArray(MAGIC.size).also { input.readFully(it) }
            if (!magic.contentEquals(MAGIC)) throw IOException("not a JARX download: $src")
            val iv = ByteArray(16).also { input.readFully(it) }
            val tmp = File("$dst.part")
            tmp.outputStream().use { out ->
                CipherInputStream(input, cipher(context, Cipher.DECRYPT_MODE, iv))
                    .use { it.copyTo(out, 1 shl 16) }
            }
            if (!tmp.renameTo(File(dst))) throw IOException("could not write $dst")
        }
    }

    private fun java.io.InputStream.readFully(buf: ByteArray) {
        var n = 0
        while (n < buf.size) {
            val r = read(buf, n, buf.size - n)
            if (r < 0) throw IOException("file too short")
            n += r
        }
    }
}
