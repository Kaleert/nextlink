package pro.kaleert.nextlink

import android.content.Context
import android.os.Build
import java.io.File
import android.system.Os

/** The shadow flavor ships executable ELF .so files in nativeLibraryDir.
 * Link to them instead of duplicating 100+ MB in filesDir.
 * Existing user-installed/updated regular files remain untouched.
 */
internal object BundledResources {
    fun install(context: Context): List<String> {
        val installed = mutableListOf<String>()
        val root = context.filesDir
        val nativeDir = File(context.applicationInfo.nativeLibraryDir)

        for (name in listOf("libxray.so", "libsingbox.so", "libawg.so")) {
            val native = File(nativeDir, name)
            val dest = File(root, name)
            if (!native.isFile || native.length() <= 1024L) {
                // Switching Shadow -> Original must not leave a dangling link:
                // downloaded replacements need a writable filesDir path.
                val oldLink = try {
                    Os.readlink(dest.absolutePath)
                } catch (_: android.system.ErrnoException) {
                    null
                }
                if (oldLink != null) check(dest.delete()) { "Cannot remove existing core link: ${dest.absolutePath}" }
                continue
            }
            // Android's Os.symlink works back to API 21. readlink throws if
            // the destination is a regular file or does not exist.
            val oldLink = try {
                Os.readlink(dest.absolutePath)
            } catch (_: android.system.ErrnoException) {
                null
            }
            if (oldLink != null) {
                if (oldLink == native.absolutePath && dest.length() > 1024L) continue
                check(dest.delete()) { "Cannot remove existing core link: ${dest.absolutePath}" }
            } else if (dest.exists()) {
                // Do not overwrite a downloaded core or the user's custom version.
                continue
            }
            Os.symlink(native.absolutePath, dest.absolutePath)
            installed += name
        }

        // Rules are data, not executable libraries, and still belong in filesDir.
        for (name in listOf("geoip.dat", "geosite.dat")) {
            val input = try {
                context.assets.open("preload/$name")
            } catch (_: java.io.IOException) {
                continue
            }
            input.use { stream ->
                val dest = File(root, name)
                if (dest.exists() && dest.length() > 1024L) return@use
                val temp = File(root, "$name.seed-tmp")
                try {
                    temp.outputStream().use { output -> stream.copyTo(output) }
                    check(temp.length() > 1024L) { "Bundled file too small: $name" }
                    check(temp.renameTo(dest)) { "Could not install $name" }
                    installed += name
                } finally { temp.delete() }
            }
        }
        return installed
    }
}
