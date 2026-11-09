package pro.kaleert.nextlink

import android.content.Context
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.AppOpsManager
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.PowerManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.provider.OpenableColumns
import android.util.Log
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.util.HashMap
import java.util.concurrent.TimeUnit
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider

class MainActivity : FlutterActivity() {
    companion object {
        private const val BATTERY_CHANNEL = "pro.kaleert.nextlink/battery"
        private const val VPN_CHANNEL = "pro.kaleert.nextlink/vpn"
        private const val APPS_CHANNEL = "pro.kaleert.nextlink/apps"
        private const val STATS_CHANNEL = "pro.kaleert.nextlink/stats"
        private const val LOGGER_CHANNEL = "pro.kaleert.nextlink/logger"
        private const val THEME_FILES_CHANNEL = "pro.kaleert.nextlink/theme_files"
        private const val VPN_REQUEST_CODE = 2400
        private const val THEME_FILE_REQUEST_CODE = 2401
        private const val THEME_EXPORT_REQUEST_CODE = 2402
        private const val QR_IMAGE_REQUEST_CODE = 2403
        
        /** One engine owns each channel. Producers may outlive the Activity. */
        private class EngineBinding(val engine: FlutterEngine) {
            val handler = Handler(Looper.getMainLooper())
            val logger = MethodChannel(engine.dartExecutor.binaryMessenger, LOGGER_CHANNEL)
            val stats = MethodChannel(engine.dartExecutor.binaryMessenger, STATS_CHANNEL)
            val vpn = MethodChannel(engine.dartExecutor.binaryMessenger, VPN_CHANNEL)
            val apps = MethodChannel(engine.dartExecutor.binaryMessenger, APPS_CHANNEL)
            val battery = MethodChannel(engine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            val themeFiles = MethodChannel(engine.dartExecutor.binaryMessenger, THEME_FILES_CHANNEL)
            var listener: FlutterEngine.EngineLifecycleListener? = null
            @Volatile var closed = false
            @Volatile var installedAppsSnapshot: List<android.content.pm.ApplicationInfo>? = null

            fun postIfCurrent(action: () -> Unit) {
                if (closed || currentBinding !== this) return
                handler.post {
                    // A queued event from the previous engine must not be
                    // delivered to either its destroyed JNI or its replacement.
                    if (!closed && currentBinding === this) action()
                }
            }
        }

        @Volatile private var currentBinding: EngineBinding? = null
        @Volatile private var activeCoreType: String? = null
        @Volatile private var activeCoreUsesJni = false
        @Volatile private var crashHandlerInstalled = false

        fun updateSubscriptionsInExistingEngine(ids: List<String>, completed: (Map<*, *>?) -> Unit): Boolean {
            val binding=currentBinding ?: return false
            if(binding.closed) return false
            binding.vpn.invokeMethod("updateSubscriptionsInBackground", mapOf("ids" to ids), object: MethodChannel.Result {
                override fun success(result: Any?) { completed(result as? Map<*, *>) }
                override fun error(code: String,message: String?,details: Any?) { completed(null) }
                override fun notImplemented() { completed(null) }
            })
            return true
        }

        private fun releaseBinding(binding: EngineBinding, removeListener: Boolean = true) {
            if (binding.closed) return
            binding.closed = true
            binding.installedAppsSnapshot = null
            binding.handler.removeCallbacksAndMessages(null)
            if (currentBinding === binding) currentBinding = null
            listOf(binding.logger, binding.stats, binding.vpn, binding.apps,
                binding.battery, binding.themeFiles).forEach { it.setMethodCallHandler(null) }
            if (removeListener) binding.listener?.let { binding.engine.removeEngineLifecycleListener(it) }
            binding.listener = null
        }

        private fun postToFlutter(action: (EngineBinding) -> Unit) {
            val binding = currentBinding ?: return
            binding.postIfCurrent {
                try { action(binding) }
                catch (error: Exception) { Log.w("MainActivity", "Unable to deliver Flutter event", error) }
            }
        }

        fun sendNativeLog(tag: String, message: String) {
            postToFlutter { it.logger.invokeMethod("onNativeLog", mapOf("tag" to tag, "message" to message)) }
        }

        fun sendNativeStats(
            speed: String,
            ping: String,
            rxBytes: Long,
            txBytes: Long,
            isWifi: Boolean = false,
            isMobile: Boolean = false,
            sessionId: String = "",
            appBytes: Map<String, Long>? = null
        ) {
            postToFlutter { binding ->
                binding.stats.invokeMethod("onStatsUpdate", mapOf(
                    "speed" to speed, "ping" to ping, "total" to (rxBytes + txBytes),
                    "rx" to rxBytes, "tx" to txBytes, "isWifi" to isWifi,
                    "isMobile" to isMobile, "sessionId" to sessionId, "appBytes" to appBytes))
            }
        }

        fun sendVpnStopped() {
            postToFlutter { it.vpn.invokeMethod("onVpnStopped", null) }
        }

        fun stopNativeCore() {
            val core = activeCoreType ?: NativeCoreLauncher.runningCoreType
            if (core == null && !NativeCoreLauncher.isRunning()) return
            sendNativeLog("CORE", "Stopping ${core ?: "unknown"} core after stopping VPN interface")
            try {
                if (activeCoreUsesJni) {
                    when (core) {
                        "SINGBOX" -> LibSingBox.stop()
                        "XRAY" -> LibXray.stop()
                    }
                } else {
                    NativeCoreLauncher.stop()
                }
            } catch (error: Throwable) {
                sendNativeLog("CORE", "Error stopping ${core ?: "unknown"} core: ${error.message}")
            } finally {
                activeCoreType = null
                activeCoreUsesJni = false
            }
        }

        fun startSavedNativeCore(
            context: Context,
            config: String,
            coreType: String,
            corePath: String?,
        ): String {
            sendNativeLog("TILE", "Starting saved $coreType configuration")
            return try {
                if (!corePath.isNullOrBlank() && File(corePath).exists()) {
                    val configFile = File(context.cacheDir, "config_${coreType.lowercase()}.json")
                    configFile.writeText(config)
                    val args = if (coreType == "SINGBOX") {
                        listOf("run", "-c", configFile.absolutePath)
                    } else {
                        listOf("-config", configFile.absolutePath)
                    }
                    val error = NativeCoreLauncher.start(context, coreType, corePath, args)
                    if (error.isEmpty()) {
                        activeCoreType = coreType
                        activeCoreUsesJni = false
                    }
                    error
                } else {
                    val error = when (coreType) {
                        "SINGBOX" -> LibSingBox.start(config)
                        else -> LibXray.start(config)
                    }
                    if (error.isEmpty()) {
                        activeCoreType = coreType
                        activeCoreUsesJni = true
                        sendNativeLog("CORE", "$coreType core started successfully (quick tile)")
                    }
                    error
                }
            } catch (error: Throwable) {
                error.message ?: "Unable to start $coreType"
            }
        }

        fun isNativeCoreRunning(): Boolean =
            if (activeCoreUsesJni) activeCoreType != null else NativeCoreLauncher.isRunning()

        fun sendVpnState(snapshot: Map<String, Any>) {
            postToFlutter { it.vpn.invokeMethod("onVpnState", snapshot) }
        }

        fun sendVpnPaused() {
            postToFlutter { it.vpn.invokeMethod("onVpnPaused", null) }
        }

        fun sendVpnResumed() {
            postToFlutter { it.vpn.invokeMethod("onVpnResumed", null) }
        }

    }

    private var activityBinding: EngineBinding? = null

    private var themeExportContents: String? = null
    private var pendingThemeExportResult: MethodChannel.Result? = null
    private var pickingThemeImage = false
    private var pendingThemeFileResult: MethodChannel.Result? = null
    private var pendingQrImageResult: MethodChannel.Result? = null

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == QR_IMAGE_REQUEST_CODE) {
            val pending = pendingQrImageResult ?: return
            pendingQrImageResult = null
            if (resultCode != RESULT_OK || data?.data == null) { pending.success(null); return }
            val binding = activityBinding
            val uri = data.data!!
            Thread { try {
                val folder = File(cacheDir, "qr_import").apply { mkdirs() }
                folder.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86400000L }?.forEach { it.delete() }
                val file = File(folder, "qr-${java.util.UUID.randomUUID()}.img")
                contentResolver.openInputStream(uri)?.use { source ->
                    file.outputStream().use { output ->
                        val buffer = ByteArray(8192); var total = 0
                        while (true) {
                            val size = source.read(buffer); if (size < 0) break
                            total += size
                            require(total <= 20 * 1024 * 1024) { "Изображение больше 20 МБ" }
                            output.write(buffer, 0, size)
                        }
                    }
                } ?: throw IllegalStateException("Не удалось прочитать изображение")
                binding?.postIfCurrent { pending.success(file.absolutePath) }
            } catch (error: Exception) { binding?.postIfCurrent { pending.error("QR_IMAGE_FAILED", error.message, null) } } }.start()
            return
        }
        if (requestCode == THEME_EXPORT_REQUEST_CODE) {
            val pending = pendingThemeExportResult
            val contents = themeExportContents
            pendingThemeExportResult = null
            themeExportContents = null
            if (resultCode != RESULT_OK || data?.data == null || contents == null) { pending?.success(false); return }
            try {
                contentResolver.openOutputStream(data.data!!)?.use { it.write(contents.toByteArray(Charsets.UTF_8)) }
                    ?: throw IllegalStateException("Unable to create theme file")
                pending?.success(true)
            } catch (error: Exception) { pending?.error("EXPORT_FAILED", error.message, null) }
            return
        }
        if (requestCode != THEME_FILE_REQUEST_CODE) return
        val pending = pendingThemeFileResult ?: return
        pendingThemeFileResult = null
        if (resultCode != RESULT_OK || data?.data == null) {
            pending.success(null)
            return
        }
        try {
            val uri = data.data!!
            if (pickingThemeImage) {
                pickingThemeImage = false
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > 16 * 1024 * 1024) throw IllegalArgumentException("Изображение больше 16 МБ")
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalStateException("Could not read image")
                pending.success(mapOf("bytes" to bytes))
                return
            }
            val contents = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                ?: throw IllegalStateException("Could not read the selected file")
            pending.success(mapOf("name" to (uri.lastPathSegment ?: "theme.json"), "contents" to contents))
        } catch (error: Exception) {
            pending.error("READ_FAILED", error.message, null)
        }
    }

    private var xrayPath: String? = null
    private var sbPath: String? = null
    private var pendingDeepLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashHandler()
        super.onCreate(savedInstanceState)
        NotificationGroupPolicy.migrate(this)
        pendingDeepLink = incomingIntentCommand(intent)
        nativeCrashLogFile()
        removeNonCrashExitReports()
        collectPreviousExitInfo()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = incomingIntentCommand(intent) ?: return
        pendingDeepLink = url
        activityBinding?.let { binding ->
            binding.postIfCurrent { binding.vpn.invokeMethod("onUrlScheme", url) }
        }
    }

    private fun incomingIntentCommand(incoming: Intent?): String? {
        incoming ?: return null
        if (incoming.action == "android.service.quicksettings.action.QS_TILE_PREFERENCES") {
            return "nextlink://servers"
        }
        val streamExtra = incoming.extras?.get(Intent.EXTRA_STREAM)
        val sharedUri = streamExtra as? Uri
            ?: (streamExtra as? ArrayList<*>)?.firstOrNull() as? Uri
        val uri = incoming.data
            ?: sharedUri
            ?: incoming.clipData?.getItemAt(0)?.uri
            ?: return null
        if (uri.scheme == "nextlink") return uri.toString()
        val displayName = try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameColumn >= 0 && cursor.moveToFirst()) cursor.getString(nameColumn) else null
            }
        } catch (_: Exception) {
            null
        }
        val fileName = (displayName ?: uri.lastPathSegment.orEmpty())
            .substringAfterLast('/')
            .lowercase()
        if (fileName.endsWith(".nlt") || fileName.endsWith(".json") || fileName.endsWith(".conf")) {
            return try {
                val stream = contentResolver.openInputStream(uri) ?: return null
                val bytes = stream.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    var total = 0
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        total += read
                        if (total > 16 * 1024 * 1024) throw IllegalArgumentException("Файл импорта больше 16 МБ")
                        output.write(buffer, 0, read)
                    }
                    output.toByteArray()
                }
                val encoded = android.util.Base64.encodeToString(
                    bytes,
                    android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING
                )
                if (fileName.endsWith(".nlt")) "nextlink://theme/$encoded" else "nextlink://file/$encoded"
            } catch (error: Exception) {
                Log.e("MainActivity", "Could not import file", error)
                "nextlink://file-error?message=" + Uri.encode(error.message ?: "Не удалось прочитать файл")
            }
        }
        return null
    }

    private fun removeNonCrashExitReports() {
        try {
            val file = nativeCrashLogFile()
            if (!file.isFile) return
            val sections = file.readText().split(Regex("(?=\\n========== )"))
            val crashReports = sections.filter { section ->
                section.contains("ANDROID CRASH") ||
                    (section.contains("PREVIOUS PROCESS EXIT") &&
                        (section.contains("Reason: JAVA_CRASH") ||
                            section.contains("Reason: NATIVE_CRASH")))
            }
            file.writeText(crashReports.joinToString(""))
        } catch (error: Exception) {
            Log.w("MainActivity", "Could not clean old non-crash reports", error)
        }
    }

    private fun collectPreviousExitInfo() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) return
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return
            val exits = activityManager.getHistoricalProcessExitReasons(packageName, 0, 8)
            val prefs = getSharedPreferences("crash_log_state", Context.MODE_PRIVATE)
            var lastLoggedTimestamp = prefs.getLong("last_exit_timestamp", 0L)
            val reportableReasons = setOf(
                ApplicationExitInfo.REASON_CRASH,
                ApplicationExitInfo.REASON_CRASH_NATIVE,
            )
            for (exit in exits.sortedBy { it.timestamp }) {
                if (exit.timestamp <= lastLoggedTimestamp || exit.reason !in reportableReasons) continue
                val trace = try {
                    exit.traceInputStream?.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        var total = 0
                        while (total < 256 * 1024) {
                            val read = input.read(buffer, 0, minOf(buffer.size, 256 * 1024 - total))
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                            total += read
                        }
                        output.toString(Charsets.UTF_8.name())
                    }.orEmpty()
                } catch (_: Exception) {
                    ""
                }
                val report = buildString {
                    appendLine("\n========== PREVIOUS PROCESS EXIT ==========")
                    appendLine("Time: ${java.time.Instant.ofEpochMilli(exit.timestamp)}")
                    appendLine("Process: ${exit.processName}")
                    appendLine("Reason: ${exitReasonName(exit.reason)} (${exit.reason})")
                    appendLine("Status/signal: ${exit.status}")
                    appendLine("Description: ${exit.description ?: "-"}")
                    appendLine("Importance: ${exit.importance}")
                    appendLine("Last RSS/PSS: ${exit.rss}/${exit.pss} KB")
                    if (trace.isNotBlank()) {
                        appendLine("System trace:")
                        appendLine(trace)
                    }
                    appendLine("===========================================\n")
                }
                appendNativeCrashReport(report)
                lastLoggedTimestamp = exit.timestamp
            }
            if (lastLoggedTimestamp > prefs.getLong("last_exit_timestamp", 0L)) {
                prefs.edit().putLong("last_exit_timestamp", lastLoggedTimestamp).apply()
            }
        } catch (error: Exception) {
            Log.w("MainActivity", "Could not read previous process exit info", error)
        }
    }

    private fun installCrashHandler() {
        if (crashHandlerInstalled) return
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val stack = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
                val report = buildString {
                    appendLine("\n========== ANDROID CRASH ==========")
                    appendLine("Time: ${java.time.Instant.now()}")
                    appendLine("Thread: ${thread.name} (id=${thread.id})")
                    appendLine("Device: ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}")
                    appendLine("Android API: ${android.os.Build.VERSION.SDK_INT}")
                    appendLine("Process: $packageName")
                    appendLine("Exception: ${error.javaClass.name}: ${error.message}")
                    appendLine("Stack trace:")
                    appendLine(stack)
                    appendLine("===================================\n")
                }
                appendNativeCrashReport(report)
            } catch (writeError: Exception) {
                Log.e("MainActivity", "Could not persist native crash log", writeError)
            }
            if (previousHandler != null) {
                previousHandler.uncaughtException(thread, error)
            } else {
                android.os.Process.killProcess(android.os.Process.myPid())
                kotlin.system.exitProcess(10)
            }
        }
        crashHandlerInstalled = true
    }

    private fun exitReasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_CRASH -> "JAVA_CRASH"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "NATIVE_CRASH"
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_FREEZER -> "APP_FREEZER"
        else -> "OTHER"
    }

    private fun appendNativeCrashReport(report: String) {
        val file = nativeCrashLogFile()
        if (file.exists() && file.length() > 1024 * 1024) {
            val old = file.readText()
            file.writeText(old.takeLast(old.length / 2))
        }
        file.appendText(report)
    }

    private fun nativeCrashLogFile(): File {
        val directory = File(filesDir, "logs").apply { mkdirs() }
        val file = File(directory, "crash_log.txt")
        val oldFiles = listOf(
            File(directory, "native_crash_log.txt"),
            File(filesDir, "native_crash_log.txt"),
        )
        for (oldFile in oldFiles) {
            if (!oldFile.exists()) continue
            if (!file.exists()) {
                oldFile.renameTo(file)
            } else {
                file.appendText(oldFile.readText())
                oldFile.delete()
            }
        }
        return file
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        SubscriptionUpdateJob.onUiAttached()
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pro.kaleert.nextlink/preload"
        ).setMethodCallHandler { call, result ->
            if (call.method != "installBundledResources") {
                result.notImplemented()
            } else {
                Thread {
                    try {
                        val installed = BundledResources.install(applicationContext)
                        runOnUiThread { result.success(installed) }
                    } catch (error: Exception) {
                        Log.e("NextlinkPreload", "Failed to seed resources", error)
                        runOnUiThread { result.error("SEED_FAILED", error.message, null) }
                    }
                }.start()
            }
        }

        
        currentBinding?.let { releaseBinding(it) }
        val binding = EngineBinding(flutterEngine)
        activityBinding = binding
        currentBinding = binding
        binding.listener = object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {
                // Hot restart retains this engine and its native channels.
            }
            override fun onEngineWillDestroy() {
                // FlutterEngine iterates its listener set here; do not mutate it.
                releaseBinding(binding, removeListener = false)
            }
        }
        flutterEngine.addEngineLifecycleListener(binding.listener!!)

        binding.themeFiles.setMethodCallHandler { call, result ->
            if (call.method == "pickQrImage") {
                if (pendingQrImageResult != null) { result.error("PICKER_BUSY", "Выбор изображения уже открыт", null); return@setMethodCallHandler }
                pendingQrImageResult = result
                try {
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        type = "image/*"; addCategory(Intent.CATEGORY_OPENABLE)
                    }, QR_IMAGE_REQUEST_CODE)
                } catch (error: Exception) { pendingQrImageResult = null; result.error("PICKER_FAILED", error.message, null) }
                return@setMethodCallHandler
            }
            if (call.method == "shareConfig") {
                try {
                    val text = call.argument<String>("text")
                    val name = call.argument<String>("name") ?: "NextLink"
                    val send = Intent(Intent.ACTION_SEND).apply {
                        putExtra(Intent.EXTRA_SUBJECT, name)
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    if (text != null) {
                        send.type = "text/plain"; send.putExtra(Intent.EXTRA_TEXT, text)
                    } else {
                        val extension = call.argument<String>("extension") ?: "json"
                        require(extension in listOf("json", "conf", "png"))
                        val folder = File(cacheDir, "shared_configs").apply { mkdirs() }
                        folder.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 7 * 86400000L }?.forEach { it.delete() }
                        val safeName = name.replace(Regex("[^\\p{L}\\p{N}._-]"), "_").take(60).ifBlank { "NextLink" }
                        val file = File(folder, "$safeName-${java.util.UUID.randomUUID()}.$extension")
                        val bytes = call.argument<ByteArray>("bytes") ?: (call.argument<String>("contents") ?: "").toByteArray(Charsets.UTF_8)
                        file.writeBytes(bytes)
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                        send.type = call.argument<String>("mime") ?: "application/octet-stream"
                        send.putExtra(Intent.EXTRA_STREAM, uri)
                        send.clipData = ClipData.newUri(contentResolver, name, uri)
                        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(send, "Поделиться").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                    result.success(null)
                } catch (error: Exception) { result.error("SHARE_CONFIG_FAILED", error.message, null) }
                return@setMethodCallHandler
            }
            if (call.method == "saveThemeFile" || call.method == "saveBackupFile") {
                if (pendingThemeExportResult != null) { result.error("PICKER_BUSY", "Export already open", null); return@setMethodCallHandler }
                pendingThemeExportResult = result
                themeExportContents = call.argument<String>("contents") ?: ""
                try {
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "NextLink.nlt")
                    }, THEME_EXPORT_REQUEST_CODE)
                } catch (error: Exception) {
                    pendingThemeExportResult = null; themeExportContents = null
                    result.error("EXPORT_FAILED", error.message, null)
                }
                return@setMethodCallHandler
            }
            if (call.method != "pickThemeFile" && call.method != "pickConfigFile" && call.method != "pickBackupFile" && call.method != "pickThemeImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingThemeFileResult != null) {
                result.error("PICKER_BUSY", "A file picker is already open", null)
                return@setMethodCallHandler
            }
            pendingThemeFileResult = result
            pickingThemeImage = call.method == "pickThemeImage"
            try {
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (pickingThemeImage) "image/*" else "*/*"
                    if (!pickingThemeImage) putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                }
                startActivityForResult(intent, THEME_FILE_REQUEST_CODE)
            } catch (error: Exception) {
                pendingThemeFileResult = null
                result.error("PICKER_FAILED", error.message, null)
            }
        }
        binding.logger.setMethodCallHandler { call, result ->
            if (call.method == "getLogTechnicalInfo") {
                try {
                    val connectivity =
                        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                    val transports = mutableListOf<String>()
                    if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) transports.add("Wi-Fi")
                    if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) transports.add("Cellular")
                    if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true) transports.add("Ethernet")
                    if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) transports.add("VPN")
                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                    @Suppress("DEPRECATION")
                    val versionCode = if (android.os.Build.VERSION.SDK_INT >= 28) {
                        packageInfo.longVersionCode
                    } else {
                        packageInfo.versionCode.toLong()
                    }
                    result.success(mapOf(
                        "Device" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
                        "Android" to "${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})",
                        "App version" to "${packageInfo.versionName ?: "unknown"} ($versionCode)",
                        "Network" to transports.joinToString().ifBlank { "Unavailable" },
                        "VPN active" to (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true).toString(),
                        "Core" to (activeCoreType ?: "stopped"),
                        "Timestamp" to java.time.Instant.now().toString(),
                    ))
                } catch (error: Exception) {
                    result.error("LOG_TECH_INFO_FAILED", error.message, null)
                }
                return@setMethodCallHandler
            }
            if (call.method == "shareLogFiles") {
                try {
                    val logDirectory = File(filesDir, "logs").canonicalFile
                    val requestedPaths = call.argument<List<String>>("paths") ?: emptyList()
                    val files = requestedPaths.mapNotNull { path ->
                        runCatching {
                            File(path).canonicalFile.takeIf { file ->
                                file.isFile && file.path.startsWith(
                                    logDirectory.path + File.separator
                                )
                            }
                        }.getOrNull()
                    }.distinctBy { it.path }
                    if (files.isEmpty()) {
                        result.error("NO_LOG_FILES", "No log files are available to share", null)
                        return@setMethodCallHandler
                    }
                    val uris = files.map { file ->
                        FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                    }
                    val sendIntent = Intent(
                        if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE
                    ).apply {
                        type = "text/plain"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (uris.size == 1) {
                            putExtra(Intent.EXTRA_STREAM, uris.first())
                        } else {
                            putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                        }
                        clipData = ClipData.newUri(contentResolver, "NextLink logs", uris.first())
                        for (uri in uris.drop(1)) clipData?.addItem(ClipData.Item(uri))
                    }
                    val chooserTitle = call.argument<String>("chooserTitle") ?: "Share logs"
                    startActivity(
                        Intent.createChooser(sendIntent, chooserTitle).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    )
                    result.success(null)
                } catch (error: Exception) {
                    result.error("SHARE_LOG_FILES_FAILED", error.message, null)
                }
                return@setMethodCallHandler
            }
            result.notImplemented()
        }

        // Apps Channel
        binding.apps.setMethodCallHandler { call, result ->
            if (call.method == "hasUsageStatsAccess") {
                val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
                val mode = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
                } else {
                    @Suppress("DEPRECATION")
                    appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
                }
                result.success(mode == AppOpsManager.MODE_ALLOWED)
            } else if (call.method == "openUsageStatsSettings") {
                try {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                } catch (error: Exception) {
                    result.error("USAGE_SETTINGS_FAILED", error.message, null)
                }
            } else if (call.method == "getInstalledApps" || call.method == "getInstalledAppsPage") {
                val paged = call.method == "getInstalledAppsPage"
                val offset = (call.argument<Int>("offset") ?: 0).coerceAtLeast(0)
                val limit = (call.argument<Int>("limit") ?: 24).coerceIn(1, 64)
                Thread {
                    try {
                        val pm = this@MainActivity.packageManager
                        val installed = if (!paged || offset == 0 || binding.installedAppsSnapshot == null) {
                            pm.getInstalledApplications(0).sortedBy { it.packageName }.also {
                                if (paged) binding.installedAppsSnapshot = it
                            }
                        } else binding.installedAppsSnapshot!!
                        val end = if (paged) (offset.toLong() + limit).coerceAtMost(installed.size.toLong()).toInt() else installed.size
                        val apps = mutableListOf<Map<String, Any>>()
                        for (appInfo in installed.subList(offset.coerceAtMost(installed.size), end)) {
                            if (binding.closed) return@Thread
                            try {
                                val name = appInfo.loadLabel(pm).toString().ifBlank { appInfo.packageName }
                                val iconBytes = runCatching {
                                    val icon = appInfo.loadIcon(pm)
                                    val bitmap = android.graphics.Bitmap.createBitmap(96, 96, android.graphics.Bitmap.Config.ARGB_8888)
                                    try {
                                        val canvas = android.graphics.Canvas(bitmap)
                                        icon.setBounds(0, 0, 96, 96)
                                        icon.draw(canvas)
                                        java.io.ByteArrayOutputStream().use { stream ->
                                            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                                            stream.toByteArray()
                                        }
                                    } finally { bitmap.recycle() }
                                }.getOrDefault(ByteArray(0))
                                apps.add(mapOf(
                                    "name" to name,
                                    "package" to appInfo.packageName,
                                    "icon" to iconBytes,
                                    "isVpnServiceApp" to (appInfo.packageName == this@MainActivity.packageName),
                                    "isSystem" to ((appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0),
                                ))
                            } catch (_: Exception) {}
                        }
                        binding.postIfCurrent {
                            if (paged) result.success(mapOf(
                                "apps" to apps,
                                "nextOffset" to end,
                                "total" to installed.size,
                                "hasMore" to (end < installed.size),
                                "supportsUidBlocking" to (Build.VERSION.SDK_INT >= 29),
                            )) else result.success(apps)
                        }
                    } catch (error: Exception) {
                        binding.postIfCurrent { result.error("APPS_LOAD_FAILED", error.message, null) }
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }

        // Battery Channel
        binding.battery.setMethodCallHandler { call, result ->
            when (call.method) {
                "openBatterySettings" -> {
                    openBatterySettings()
                    result.success(null)
                }
                "isBatteryOptimizationDisabled" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val isIgnoring = pm.isIgnoringBatteryOptimizations(packageName)
                    result.success(isIgnoring)
                }
                else -> result.notImplemented()
            }
        }

        // VPN Channel
        binding.vpn.setMethodCallHandler { call, result ->
            when (call.method) {
                "storeAutomationPlan" -> {
                    try { AutomationService.store(this, call.argument<String>("plan") ?: "{}"); result.success(null) }
                    catch (error: Exception) { result.error("AUTOMATION_PLAN_FAILED", error.message, null) }
                }
                "syncAutomation" -> {
                    try { AutomationService.sync(this, call.argument<String>("plan") ?: "{}"); result.success(null) }
                    catch (error: Exception) { result.error("AUTOMATION_FAILED", error.message, null) }
                }
                "scheduleSubscriptionUpdates" -> { SubscriptionUpdateJob.schedule(this); result.success(null) }
                "getPendingTraffic" -> result.success(VpnTrafficJournal.pending(this))
                "acknowledgeTraffic" -> {
                    VpnTrafficJournal.acknowledge(this, call.argument<String>("sessionId") ?: "",
                        call.argument<Number>("rx")?.toLong() ?: 0L, call.argument<Number>("tx")?.toLong() ?: 0L)
                    result.success(null)
                }
                "notifySubscriptionUpdated" -> { SubscriptionUpdateJob.notifyUpdated(this, call.argument<Int>("count") ?: 0); result.success(null) }
                "stopAutomation" -> { stopService(Intent(this, AutomationService::class.java)); result.success(null) }
                "getAutomationHistory" -> { result.success(AutomationService.history(this).toString()) }
                "clearAutomationHistory" -> { getSharedPreferences(AutomationService.PREFS, MODE_PRIVATE).edit().remove("history").apply(); result.success(null) }
                "getAwgCorePath" -> {
                    val downloaded = File(filesDir, "libawg.so")
                    val binary = downloaded
                    if (binary.isFile) result.success(binary.absolutePath) else result.error("AWG_CORE_MISSING", "Загрузите ядро WG в Центре ресурсов", null)
                }
                "getInitialUrl" -> {
                    result.success(pendingDeepLink)
                    pendingDeepLink = null
                }
                "openVpnSystemSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_VPN_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("VPN_SETTINGS_FAILED", error.message, null)
                    }
                }
                "getNetworkEnvironment" -> {
                    try {
                        val manager =
                            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        val networks = manager.allNetworks.mapNotNull { network ->
                            val capabilities = manager.getNetworkCapabilities(network) ?: return@mapNotNull null
                            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                            ) return@mapNotNull null
                            when {
                                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                                else -> null
                            }
                        }.sortedBy { network ->
                            when (network) {
                                "wifi" -> 0
                                "mobile" -> 1
                                "ethernet" -> 2
                                else -> 3
                            }
                        }
                        val interfaces = try {
                            java.util.Collections.list(java.net.NetworkInterface.getNetworkInterfaces())
                                .map { it.name.lowercase() }
                        } catch (_: Exception) {
                            emptyList()
                        }
                        val hotspotFromInterface = interfaces.any { name ->
                            name.startsWith("ap") || name.startsWith("softap") ||
                                name == "wlan1" || name == "rndis0" ||
                                name == "usb0" || name == "bt-pan"
                        }
                        val hotspotFromWifiManager = try {
                            val wifiManager =
                                applicationContext.getSystemService(Context.WIFI_SERVICE)
                            val isEnabled = try {
                                val method = wifiManager.javaClass.getDeclaredMethod("isWifiApEnabled")
                                method.isAccessible = true
                                method.invoke(wifiManager) as? Boolean == true
                            } catch (_: Exception) {
                                false
                            }
                            val apState = try {
                                val method = wifiManager.javaClass.getDeclaredMethod("getWifiApState")
                                method.isAccessible = true
                                (method.invoke(wifiManager) as? Number)?.toInt() == 13
                            } catch (_: Exception) {
                                false
                            }
                            isEnabled || apState
                        } catch (_: Exception) {
                            false
                        }
                        result.success(
                            mapOf(
                                "network" to (networks.firstOrNull() ?: "none"),
                                "hotspot" to (hotspotFromInterface || hotspotFromWifiManager),
                            )
                        )
                    } catch (error: Exception) {
                        result.error("NETWORK_ENVIRONMENT_FAILED", error.message, null)
                    }
                }
                "resolveHostDirect" -> {
                    val host = call.argument<String>("host")?.trim()
                    if (host.isNullOrBlank()) {
                        result.error("INVALID_HOST", "Host is empty", null)
                    } else {
                        Thread {
                            try {
                                val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                                val physicalNetwork = manager.allNetworks.firstOrNull { network ->
                                    val caps = manager.getNetworkCapabilities(network)
                                    caps != null &&
                                        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                                        !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                                        (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                                            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                                            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))
                                } ?: throw IllegalStateException("Нет доступной сети для прямого DNS")
                                val addresses = physicalNetwork.getAllByName(host)
                                    .map { it.hostAddress ?: "" }
                                    .filter { it.isNotBlank() }
                                    .distinct()
                                binding.postIfCurrent {
                                    result.success(addresses)
                                }
                            } catch (error: Exception) {
                                binding.postIfCurrent {
                                    result.error("DIRECT_DNS_FAILED", error.message, null)
                                }
                            }
                        }.start()
                    }
                }
                "openExternalUrl" -> {
                    val url = call.arguments as? String
                        ?: (call.arguments as? Map<*, *>)?.get("url") as? String
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "URL is empty", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            })
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_URL_FAILED", e.message, null)
                        }
                    }
                }
                "prepareVpn" -> {
                    val intent = android.net.VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                "startVpn" -> {
                    val config = call.argument<String>("config") ?: ""
                    val coreType = call.argument<String>("coreType") ?: "XRAY"
                    val serverName = call.argument<String>("serverName") ?: "Unknown"

                    xrayPath = call.argument<String>("xrayPath")
                    sbPath = call.argument<String>("sbPath")

                    // НОВЫЕ АРГУМЕНТЫ
                    val perAppEnabled = call.argument<Boolean>("perAppEnabled") ?: false
                    val perAppDefaultRule = call.argument<String>("perAppDefaultRule") ?: "proxy"
                    val perAppRules = call.argument<Map<String, String>>("perAppRules") ?: mapOf()

                    val tunMtu = call.argument<Int>("tunMtu") ?: 1500
                    val ipv6 = call.argument<Boolean>("ipv6") ?: false
                    val strictMode = call.argument<Boolean>("strictMode") ?: true
                    val bypassLan = call.argument<Boolean>("bypassLan") ?: false
                    val socksPort = call.argument<Int>("socksPort") ?: 10808
                    val httpPort = call.argument<Int>("httpPort") ?: 10809

                    val tilePrefs = getSharedPreferences("quick_tile_vpn", Context.MODE_PRIVATE)
                    tilePrefs.edit()
                        .putString("config", config)
                        .putString("coreType", coreType)
                        .putString("corePath", if (coreType == "SINGBOX") sbPath else xrayPath)
                        .putString("serverName", serverName)
                        .putString("serverKey", call.argument<String>("serverKey") ?: "")
                        .putBoolean("perAppEnabled", perAppEnabled)
                        .putString("perAppDefaultRule", perAppDefaultRule)
                        .putString("perAppRules", org.json.JSONObject(perAppRules).toString())
                        .putInt("tunMtu", tunMtu)
                        .putBoolean("ipv6", ipv6)
                        .putBoolean("strictMode", strictMode)
                        .putBoolean("bypassLan", bypassLan)
                        .putInt("socksPort", socksPort)
                        .putInt("httpPort", httpPort)
                        .apply()

                    val err = startNativeCore(config, coreType)
                    if (err.isEmpty()) {
                        val intent = Intent(this, VpnTunnelService::class.java).apply {
                            putExtra("config", config)
                            putExtra("serverName", serverName)
                            putExtra("serverKey", call.argument<String>("serverKey") ?: "")
                            putExtra("perAppEnabled", perAppEnabled)
                            putExtra("perAppDefaultRule", perAppDefaultRule)
                            putExtra("perAppRules", HashMap(perAppRules))
                            putExtra("tunMtu", tunMtu)
                            putExtra("ipv6", ipv6)
                            putExtra("strictMode", strictMode)
                            putExtra("bypassLan", bypassLan)
                            putExtra("socksPort", socksPort)
                            putExtra("httpPort", httpPort)
                        }
                        startService(intent)
                        result.success(null)
                    } else {
                        result.error("CORE_ERROR", err, null)
                    }
                }
                "startTestCore" -> {
                    val config = call.argument<String>("config") ?: ""
                    val coreType = call.argument<String>("coreType") ?: "XRAY"
                    
                    xrayPath = call.argument<String>("xrayPath")
                    sbPath = call.argument<String>("sbPath")

                    val err = startNativeCore(config, coreType, isTest = true)
                    if (err.isEmpty()) {
                        result.success(null)
                    } else {
                        result.error("CORE_ERROR", err, null)
                    }
                }
                "stopTestCore" -> {
                    NativeCoreLauncher.stopTest()
                    result.success(null)
                }
                "updateVpn" -> {
                    val config = call.argument<String>("config") ?: ""
                    val coreType = call.argument<String>("coreType") ?: "XRAY"
                    val serverName = call.argument<String>("serverName") ?: "Unknown"

                    xrayPath = call.argument<String>("xrayPath")
                    sbPath = call.argument<String>("sbPath")

                    getSharedPreferences("quick_tile_vpn", Context.MODE_PRIVATE).edit()
                        .putString("config", config)
                        .putString("coreType", coreType)
                        .putString("corePath", if (coreType == "SINGBOX") sbPath else xrayPath)
                        .putString("serverName", serverName)
                        .putString("serverKey", call.argument<String>("serverKey") ?: "")
                        .apply()

                    // startNativeCore внутри себя сначала делает stop() старому ядру!
                    val err = startNativeCore(config, coreType)
                    if (err.isEmpty()) {
                        // Обновляем имя сервера в шторке уведомлений (не трогая сам туннель)
                        val intent = Intent(this, VpnTunnelService::class.java).apply {
                            action = "UPDATE_SERVER"
                            putExtra("serverName", serverName)
                            putExtra("serverKey", call.argument<String>("serverKey") ?: "")
                        }
                        startService(intent)
                        result.success(null)
                    } else {
                        result.error("CORE_ERROR", err, null)
                    }
                }
                "stopVpn" -> {
                    val intent = Intent(this, VpnTunnelService::class.java).apply {
                        action = "STOP"
                    }
                    startService(intent)
                    result.success(null)
                }
                "resumeVpn" -> {
                    startService(Intent(this, VpnTunnelService::class.java).apply { action = "RESUME" })
                    result.success(null)
                }
                "getVpnState" -> result.success(VpnTunnelService.snapshot() + mapOf("coreRunning" to isNativeCoreRunning()))
                "isRunning" -> {
                    // VPN считается работающим, только если жив и сервис туннеля, и сам бинарник ядра
                    val coreAlive = isNativeCoreRunning()
                    val tunAlive = VpnTunnelService.hasActiveTunnel
                    result.success(tunAlive && coreAlive && !VpnTunnelService.isPaused)
                }
                "isTestCoreRunning" -> {
                    result.success(NativeCoreLauncher.isTestRunning())
                }
                "getCoreVersion" -> {
                    val xrayVer = try { LibXray.getVersion() } catch(e: Throwable) { "Xray N/A" }
                    val sbVer = try { LibSingBox.getVersion() } catch(e: Throwable) { "SB N/A" }
                    result.success("Cores: $xrayVer | $sbVer")
                }
                "getCoreMemory" -> {
                    val core = activeCoreType ?: NativeCoreLauncher.runningCoreType
                    if (core == null) {
                        result.success(null)
                    } else if (activeCoreUsesJni) {
                        // JNI cores share the app process. PSS here includes Flutter and
                        // Android runtime memory, so it cannot be reported as core usage.
                        result.success(
                            mapOf(
                                "core" to core,
                                "memoryMb" to null,
                                "embedded" to true,
                            )
                        )
                    } else if (!NativeCoreLauncher.isRunning()) {
                        result.success(null)
                    } else {
                        val coreRssMb = NativeCoreLauncher.processMemoryMb()
                        if (coreRssMb == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        result.success(
                            mapOf(
                                "core" to core,
                                "memoryMb" to coreRssMb,
                            )
                        )
                    }
                }
                "hasNativeCurl" -> result.success(File("/system/bin/curl").canExecute())
                "runNetworkDiagnostic" -> {
                    val tool = call.argument<String>("tool")
                    val host = call.argument<String>("host")?.trim()
                    val args = call.argument<List<String>>("args") ?: emptyList()
                    val timeoutSeconds = (call.argument<Int>("timeoutSeconds") ?: 45)
                        .coerceIn(1, 90)
                    val requestId = call.argument<String>("requestId")
                    val proxyPort = call.argument<Int>("proxyPort")
                    if (tool == null || tool !in setOf("ping", "curl") || host.isNullOrBlank()) {
                        result.error("INVALID_DIAGNOSTIC", "Invalid tool or target", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val command = if (tool == "curl") mutableListOf("/system/bin/curl", "--no-buffer")
                                else mutableListOf("/system/bin/toybox", tool)
                            command.addAll(args.take(128))
                            if (tool == "curl") {
                                command.addAll(listOf("--silent", "--show-error", "--proto", "=http,https", "--proto-redir", "=http,https"))
                                if (proxyPort != null) command.addAll(listOf("--proxy", "http://127.0.0.1:$proxyPort", "--noproxy", ""))
                                command.add("--url")
                            }
                            command.add(host)
                            val process = ProcessBuilder(command)
                                .redirectErrorStream(true)
                                .start()
                            val output = StringBuilder()
                            val outputReader = Thread {
                                runCatching {
                                    process.inputStream.bufferedReader().use { reader ->
                                        val chars = CharArray(2048)
                                        while (true) {
                                            val size = reader.read(chars)
                                            if (size < 0) break
                                            val chunk = String(chars, 0, size)
                                            synchronized(output) {
                                                if (output.length < 256 * 1024) {
                                                    output.append(chunk.take(256 * 1024 - output.length))
                                                    if (requestId != null) binding.postIfCurrent {
                                                        MethodChannel(binding.engine.dartExecutor.binaryMessenger, "pro.kaleert.nextlink/diagnostic_output")
                                                            .invokeMethod("chunk", mapOf("requestId" to requestId, "text" to chunk))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }.apply { start() }
                            val completed = process.waitFor(timeoutSeconds.toLong(), TimeUnit.SECONDS)
                            if (!completed) {
                                process.destroyForcibly()
                                process.waitFor(2, TimeUnit.SECONDS)
                            }
                            outputReader.join(2_000)
                            val outputText = synchronized(output) { output.toString() }
                            binding.postIfCurrent {
                                result.success(
                                    mapOf(
                                        "output" to outputText,
                                        "exitCode" to if (completed) process.exitValue() else -1,
                                        "timedOut" to !completed,
                                    )
                                )
                            }
                        } catch (e: Exception) {
                            binding.postIfCurrent {
                                result.error("DIAGNOSTIC_FAILED", e.message, null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        val binding = activityBinding
        if (binding != null && binding.engine === flutterEngine) {
            releaseBinding(binding)
            activityBinding = null
            pendingThemeFileResult = null
            pendingQrImageResult = null
            pendingThemeExportResult = null
            themeExportContents = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun startNativeCore(config: String, coreType: String, isTest: Boolean = false): String {
        sendNativeLog("CORE", "Starting ${if (isTest) "Test " else ""}VPN (Target Core: $coreType)...")
        Log.d("MainActivity", "Config length: ${config.length}")

        return tryRunCore(coreType, config, isTest)
    }

    private fun tryRunCore(type: String, config: String, isTest: Boolean = false): String {
        val path = when (type) {
            "SINGBOX" -> sbPath
            else -> xrayPath
        }

        if (path != null && File(path).exists()) {
            sendNativeLog("CORE", "Launching ${if (isTest) "Test " else ""}$type from path: $path")
            
            // Write config to temp file
            val configFile = File(cacheDir, "config_${type.lowercase()}${if (isTest) "_test" else ""}.json")
            try {
                configFile.writeText(config)
                Log.d("MainActivity", "Config written to ${configFile.absolutePath}")
            } catch (e: Exception) {
                return "Failed to write config: ${e.message}"
            }
            
            val args = when (type) {
                "SINGBOX" -> listOf("run", "-c", configFile.absolutePath)
                else -> listOf("-config", configFile.absolutePath)
            }
            
            val err = NativeCoreLauncher.start(this, type, path, args, isTest)
            if (err.isEmpty()) {
                if (!isTest) {
                    activeCoreType = type
                    activeCoreUsesJni = false
                }
                return ""
            }
            return err
        }

        // Fallback to JNI
        if (isTest) return "Test core must be binary"
        return try {
            val res = when (type) {
                "SINGBOX" -> LibSingBox.start(config)
                else -> LibXray.start(config)
            }
            if (res.isEmpty()) {
                activeCoreType = type
                activeCoreUsesJni = true
                sendNativeLog("CORE", "$type core started successfully (JNI)")
            }
            res
        } catch (e: UnsatisfiedLinkError) {
            "Binary/Library for $type not found"
        } catch (e: Exception) {
            e.message ?: "Unknown native error"
        }
    }

    private fun openBatterySettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            val fallbackIntent = Intent(Settings.ACTION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallbackIntent)
        }
    }
}
