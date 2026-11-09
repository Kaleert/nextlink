package pro.kaleert.nextlink

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.InputStream
import java.util.Scanner
import kotlin.concurrent.thread

object NativeCoreLauncher {
    private var process: Process? = null
    private var testProcess: Process? = null
    private const val TAG = "NativeCoreLauncher"
    @Volatile var runningCoreType: String? = null
        private set

    fun start(context: Context, coreType: String, binaryPath: String, args: List<String>, isTest: Boolean = false): String {
        try {
            if (isTest) {
                stopTest()
            } else {
                stop() // Ensure previous process is stopped
            }

            // APK updates move nativeLibraryDir; persisted automation plans may
            // still hold the previous installation's path.
            val effectivePath = if (File(binaryPath).name == "libamneziabox.so")
                File(context.filesDir, "libawg.so").absolutePath else binaryPath
            val binaryFile = File(effectivePath)
            if (!binaryFile.exists()) {
                return "Binary not found at $binaryPath"
            }

            binaryFile.setReadable(true, false)
            try {
                binaryFile.setExecutable(true, false)
            } catch (e: Exception) {
                Log.w(TAG, "Could not set executable bit, proceeding with linker")
            }

            val abi = Build.SUPPORTED_ABIS[0]
            val linker = if (abi.contains("64")) "/system/bin/linker64" else "/system/bin/linker"
            
            // APK-installed PIE programs are executable under Android W^X rules.
            // Running an Android Go binary via linker manually adds the binary
            // path to os.Args, which Cobra interprets as an unknown command.
            val isBundled = binaryFile.canonicalFile.parentFile == File(context.applicationInfo.nativeLibraryDir).canonicalFile
            val command = if (isBundled) mutableListOf(effectivePath) else mutableListOf(linker, effectivePath)
            command.addAll(args)
            
            Log.d(TAG, "Launching ${if (isTest) "TEST " else ""}: ${command.joinToString(" ")}")
            MainActivity.sendNativeLog("INIT", "Launching $coreType${if (isTest) " (Test)" else ""}: ${command.joinToString(" ")}")

            val pb = ProcessBuilder(command)
            pb.directory(context.filesDir)
            
            val env = pb.environment()
            val nativeLibDir = context.applicationInfo.nativeLibraryDir
            val filesDir = context.filesDir.absolutePath
            env["LD_LIBRARY_PATH"] = "$nativeLibDir:$filesDir"
            
            // Critical for rule file loading
            env["XRAY_LOCATION_ASSET"] = filesDir
            env["SINGBOX_LOCATION_ASSET"] = filesDir

            env["ENABLE_DEPRECATED_OUTBOUND_DNS_RULE_ITEM"] = "true"
            env["ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER"] = "true"
            
            pb.redirectErrorStream(true)
            
            val p = pb.start()
            if (isTest) {
                testProcess = p
            } else {
                process = p
                runningCoreType = coreType
            }

            thread(start = true, name = "$coreType${if (isTest) "-test" else ""}-logger") {
                captureLogs(p.inputStream, coreType, isTest)
                try {
                    val exitCode = p.waitFor()
                    MainActivity.sendNativeLog(coreType, "${if (isTest) "Test " else ""}Process exited with code $exitCode")
                } catch (e: Exception) {
                    MainActivity.sendNativeLog(coreType, "${if (isTest) "Test " else ""}Process wait error: ${e.message}")
                }
            }

            return "" 
        } catch (e: Exception) {
            val errMsg = e.message ?: "Unknown error"
            Log.e(TAG, "Failed to start $coreType: $errMsg", e)
            MainActivity.sendNativeLog("ERROR", "Failed to start $coreType: $errMsg")
            return errMsg
        }
    }

    private fun captureLogs(inputStream: InputStream, tag: String, isTest: Boolean) {
        val scanner = Scanner(inputStream)
        try {
            while (scanner.hasNextLine() && (if (isTest) testProcess != null else process != null)) {
                val line = scanner.nextLine()
                MainActivity.sendNativeLog(if (isTest) "$tag-TEST" else tag, line)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Log capture error for $tag: ${e.message}")
        } finally {
            scanner.close()
        }
    }

    fun stop() {
        process?.destroy()
        val p = process
        if (p != null) {
            thread(start = true) {
                Thread.sleep(1000)
                try {
                    p.destroyForcibly()
                } catch (e: Exception) {}
            }
        }
        process = null
        runningCoreType = null
    }

    fun stopTest() {
        testProcess?.destroy()
        val p = testProcess
        if (p != null) {
            thread(start = true) {
                Thread.sleep(1000)
                try {
                    p.destroyForcibly()
                } catch (e: Exception) {}
            }
        }
        testProcess = null
    }

    fun isRunning(): Boolean {
        return try {
            process?.exitValue()
            false
        } catch (e: IllegalThreadStateException) {
            true
        } catch (e: Exception) {
            false
        }
    }

    fun processMemoryMb(): Double? {
        val current = process ?: return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null

        return try {
            val pid = runCatching {
                (current.javaClass.getMethod("pid").invoke(current) as? Number)?.toLong()
            }.getOrNull()
                ?: runCatching {
                    val pidField = current.javaClass.declaredFields.firstOrNull {
                        it.name.equals("pid", ignoreCase = true)
                    } ?: return@runCatching null
                    pidField.isAccessible = true
                    (pidField.get(current) as? Number)?.toLong()
                }.getOrNull()
                ?: Regex("pid=(\\d+)").find(current.toString())?.groupValues?.get(1)?.toLongOrNull()
                ?: return null
            File("/proc/$pid/status").useLines { lines ->
                val rssLine = lines.firstOrNull { it.startsWith("VmRSS:") }
                val kilobytes = rssLine?.substringAfter(':')?.trim()?.substringBefore(' ')?.toDoubleOrNull()
                kilobytes?.div(1024.0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not read core RSS: ${e.message}")
            null
        }
    }

    fun isTestRunning(): Boolean {
        return try {
            testProcess?.exitValue()
            false
        } catch (e: IllegalThreadStateException) {
            true
        } catch (e: Exception) {
            false
        }
    }
}
