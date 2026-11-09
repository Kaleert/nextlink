package pro.kaleert.nextlink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.IpPrefix
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.SystemClock
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong
import t2swrapper.T2swrapper

class VpnTunnelService : VpnService() {
    private val tunnelLifecycleLock = Any()
    private var vpnInterface: ParcelFileDescriptor? = null
    private var tunnelStartThread: Thread? = null
    private var tun2SocksStarted = false
    @Volatile private var stopping = false
    private val serviceScope = CoroutineScope(Dispatchers.Main + Job())
    private var statsJob: Job? = null
    private var serverName: String = "Unknown"
    private var lastSpeed: String = "0 B/s"
    private var lastPing: String = "---"
    private var lastIntent: Intent? = null
    private var automationJob: Job? = null
    private var serverKey: String = ""
    private var trafficSessionId: String = ""
    private var uidPolicy: AppUidPolicy? = null
    private var appUidPackages: Map<Int, String> = emptyMap()
    private var trafficSessionStartedAt: Long = 0L
    @Volatile private var paused = false

    @Volatile private var vpnStatus = "stopped"
    private var elapsedBeforePause = 0L
    private var connectedAtElapsed = 0L
    private var timerSessionId = ""

    private fun stateSnapshot(): Map<String, Any> = synchronized(tunnelLifecycleLock) { mapOf(
        "status" to vpnStatus,
        "revision" to stateRevision.get(),
        "serverName" to serverName,
        "serverKey" to serverKey,
        "sessionId" to trafficSessionId,
        "timerSessionId" to timerSessionId,
        "elapsedMilliseconds" to (elapsedBeforePause + if (vpnStatus == "connected")
            (SystemClock.elapsedRealtime() - connectedAtElapsed).coerceAtLeast(0L) else 0L),
        "elapsedSeconds" to ((elapsedBeforePause + if (vpnStatus == "connected")
            (SystemClock.elapsedRealtime() - connectedAtElapsed).coerceAtLeast(0L) else 0L) / 1000),
        "speed" to lastSpeed,
        "ping" to lastPing,
    ) }

    private fun publishState() {
        stateRevision.incrementAndGet()
        refreshQuickTile()
        MainActivity.sendVpnState(snapshot())
    }

    companion object {
        private val stateRevision = AtomicLong(0)
        @Volatile private var instance: VpnTunnelService? = null
        fun snapshot(): Map<String, Any> = instance?.stateSnapshot()
            ?: mapOf("status" to "stopped", "elapsedSeconds" to 0L, "revision" to stateRevision.get())

        private const val CHANNEL_ID = "vpn_notifications"
        private const val NOTIFICATION_ID = 101
        private const val ACTION_STOP = "STOP"
        private const val ACTION_PING = "PING"
        private const val ACTION_PAUSE = "PAUSE"
        private const val ACTION_RESUME = "RESUME"
        const val ACTION_AUTOMATION = "pro.kaleert.nextlink.action.AUTOMATION"
        const val ACTION_TILE_TOGGLE = "pro.kaleert.nextlink.action.TILE_TOGGLE"
        const val ACTION_START_SAVED = "pro.kaleert.nextlink.action.START_SAVED"

        var isAlive: Boolean = false
            private set
        @Volatile var isPaused: Boolean = false
            private set
        @Volatile var hasActiveTunnel: Boolean = false
            private set
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        isAlive = true
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_AUTOMATION) {
            // Promotion must precede parsing or core startup when launched from background.
            startForegroundService(startStats = false)
            automationJob?.cancel()
            automationJob = serviceScope.launch {
                try {
                    val target = org.json.JSONObject(intent?.getStringExtra("automationTarget") ?: "{}")
                    val tunnel = org.json.JSONObject(intent?.getStringExtra("automationTunnel") ?: "{}")
                    if (tun2SocksStarted) pauseTunnel()
                    vpnStatus = "starting"
                    paused = false
                    isPaused = false
                    publishState()
                    val error = withContext(Dispatchers.IO) {
                        MainActivity.startSavedNativeCore(this@VpnTunnelService, target.getString("config"), target.getString("coreType"), target.optString("corePath").takeIf { it.isNotBlank() })
                    }
                    if (error.isNotEmpty()) throw IllegalStateException(error)
                    val rules = HashMap<String, String>()
                    val rawRules = tunnel.optJSONObject("perAppRules") ?: org.json.JSONObject()
                    rawRules.keys().forEach { rules[it] = rawRules.getString(it) }
                    val saved = Intent(this@VpnTunnelService, VpnTunnelService::class.java).apply {
                        putExtra("config", target.getString("config"))
                        putExtra("serverName", target.getString("name"))
                        putExtra("serverKey", target.getString("key"))
                        putExtra("perAppEnabled", tunnel.optBoolean("perAppEnabled"))
                        putExtra("perAppDefaultRule", tunnel.optString("perAppDefaultRule", "proxy"))
                        putExtra("perAppRules", rules)
                        putExtra("tunMtu", tunnel.optInt("tunMtu", 1500))
                        putExtra("ipv6", tunnel.optBoolean("ipv6"))
                        putExtra("strictMode", tunnel.optBoolean("strictMode", true))
                        putExtra("socksPort", tunnel.optInt("socksPort", 10808))
                        putExtra("httpPort", tunnel.optInt("httpPort", 10809))
                    }
                    getSharedPreferences("quick_tile_vpn", MODE_PRIVATE).edit().apply {
                        putString("config", target.getString("config")); putString("serverName", target.getString("name")); putString("serverKey", target.getString("key"))
                        putString("coreType", target.getString("coreType")); putString("corePath", target.optString("corePath"))
                        putBoolean("perAppEnabled", tunnel.optBoolean("perAppEnabled")); putString("perAppDefaultRule", tunnel.optString("perAppDefaultRule", "proxy")); putString("perAppRules", rawRules.toString())
                        putInt("tunMtu", tunnel.optInt("tunMtu", 1500)); putBoolean("ipv6", tunnel.optBoolean("ipv6")); putBoolean("strictMode", tunnel.optBoolean("strictMode", true)); putInt("socksPort", tunnel.optInt("socksPort", 10808)); putInt("httpPort", tunnel.optInt("httpPort", 10809))
                    }.apply()
                    onStartCommand(saved, flags, startId)
                } catch (error: Exception) {
                    if (error is CancellationException) throw error
                    MainActivity.sendNativeLog("AUTOMATION", "Cannot apply server: ${error.javaClass.simpleName}")
                    stopVpn()
                }
            }
            return START_NOT_STICKY
        }
        if (action == ACTION_TILE_TOGGLE || action == ACTION_START_SAVED) {
            // Boot/start commands are idempotent, unlike the quick tile toggle.
            if (action == ACTION_START_SAVED &&
                (hasActiveTunnel || isPaused || vpnStatus == "starting")) return START_STICKY
            if (isPaused) {
                resumeTunnel()
                return START_STICKY
            }
            if (hasActiveTunnel || vpnStatus == "starting") {
                getSharedPreferences(AutomationService.PREFS, MODE_PRIVATE).edit().putLong("userStopAt", System.currentTimeMillis()).apply()
                stopVpn()
                return START_STICKY
            }
            // A tile tap starts this as a foreground service. Promote it before
            // reading preferences or launching the core, even on the no-config path.
            vpnStatus = "starting"
            startForegroundService(startStats = false)
            publishState()
            val prefs = getSharedPreferences("quick_tile_vpn", Context.MODE_PRIVATE)
            val savedConfig = prefs.getString("config", null)
            val coreType = prefs.getString("coreType", null)
            val corePath = prefs.getString("corePath", null)
            if (savedConfig.isNullOrBlank() || coreType.isNullOrBlank()) {
                MainActivity.sendNativeLog("TILE", "No saved VPN configuration; connect once from NextLink first")
                stopVpn()
                return START_NOT_STICKY
            }
            val savedIntent = Intent(this, VpnTunnelService::class.java).apply {
                putExtra("config", savedConfig)
                putExtra("serverKey", prefs.getString("serverKey", ""))
                putExtra("serverName", prefs.getString("serverName", "NextLink"))
                putExtra("coreType", coreType)
                putExtra("corePath", corePath)
                putExtra("perAppEnabled", prefs.getBoolean("perAppEnabled", false))
                putExtra("perAppDefaultRule", prefs.getString("perAppDefaultRule", "proxy"))
                putExtra("tunMtu", prefs.getInt("tunMtu", 1500))
                putExtra("ipv6", prefs.getBoolean("ipv6", false))
                putExtra("strictMode", prefs.getBoolean("strictMode", true))
                putExtra("socksPort", prefs.getInt("socksPort", 10808))
                putExtra("httpPort", prefs.getInt("httpPort", 10809))
                val rulesJson = org.json.JSONObject(prefs.getString("perAppRules", "{}") ?: "{}")
                val rules = HashMap<String, String>()
                rulesJson.keys().forEach { key -> rules[key] = rulesJson.optString(key) }
                putExtra("perAppRules", rules)
            }
            lastIntent = savedIntent
            serverName = savedIntent.getStringExtra("serverName") ?: "NextLink"
            updateNotification(lastSpeed, lastPing)
            val startError = MainActivity.startSavedNativeCore(this, savedConfig, coreType, corePath)
            if (startError.isNotEmpty()) {
                MainActivity.sendNativeLog("TILE", "Could not start saved VPN: $startError")
                stopVpn()
                return START_NOT_STICKY
            }
            // Reuse normal session initialization, including per-app counters.
            return onStartCommand(savedIntent, flags, startId)
        }
        if (action == ACTION_PAUSE) {
            pauseTunnel()
            return START_STICKY
        }
        if (action == ACTION_RESUME) {
            resumeTunnel()
            return START_STICKY
        }
        if (action == ACTION_STOP) {
            getSharedPreferences(AutomationService.PREFS, MODE_PRIVATE).edit().putLong("userStopAt", System.currentTimeMillis()).apply()
            MainActivity.sendNativeLog("TUN", "Stopping VPN via Notification")
            stopVpn()
            return START_NOT_STICKY
        }

        if (action == ACTION_PING) {
            serviceScope.launch {
                lastPing = getPing()
                updateNotification(lastSpeed, lastPing)
            }
            return START_STICKY
        }

        if (action == "UPDATE_SERVER") {
            synchronized(tunnelLifecycleLock) {
            serverName = intent?.getStringExtra("serverName") ?: "Unknown"
            serverKey = intent?.getStringExtra("serverKey") ?: serverKey
            lastIntent?.putExtra("serverName", serverName)
            lastIntent?.putExtra("serverKey", serverKey)
            timerSessionId = java.util.UUID.randomUUID().toString()
            elapsedBeforePause = 0L
            connectedAtElapsed = SystemClock.elapsedRealtime()
            }
            MainActivity.sendNativeLog("TUN", "Updating VPN status to $serverName")
            updateNotification(lastSpeed, lastPing)
            publishState()
            return START_STICKY
        }

        synchronized(tunnelLifecycleLock) {
            vpnStatus = "starting"
            timerSessionId = java.util.UUID.randomUUID().toString()
            elapsedBeforePause = 0L
        }
        lastIntent = intent
        paused = false
        isPaused = false
        serverName = intent?.getStringExtra("serverName") ?: "Unknown"
        serverKey = intent?.getStringExtra("serverKey") ?: ""
        val configJson = intent?.getStringExtra("config")

        if (configJson.isNullOrEmpty() || configJson == "null") {
            MainActivity.sendNativeLog("TUN", "VPN Start aborted: Empty configuration")
            stopVpn()
            return START_NOT_STICKY
        }

        MainActivity.sendNativeLog("TUN", "Starting VPN Foreground Service for $serverName")

        T2swrapper.resetTraffic()
        T2swrapper.setOwnerResolver(object : t2swrapper.OwnerResolver {
            override fun lookupOwner(protocol: Int, source: String, sourcePort: Int, destination: String, destinationPort: Int): Int {
                if (Build.VERSION.SDK_INT < 29) return -1
                return runCatching {
                    val manager = getSystemService(ConnectivityManager::class.java)
                    manager.getConnectionOwnerUid(protocol,
                        java.net.InetSocketAddress(java.net.InetAddress.getByName(source), sourcePort),
                        java.net.InetSocketAddress(java.net.InetAddress.getByName(destination), destinationPort))
                }.getOrDefault(-1)
            }
        })
        trafficSessionId = System.currentTimeMillis().toString()
        val installedApps = packageManager
            .getInstalledApplications(android.content.pm.PackageManager.GET_META_DATA)
        val perAppEnabled = intent?.getBooleanExtra("perAppEnabled", false) ?: false
        val perAppDefaultRule = intent?.getStringExtra("perAppDefaultRule") ?: "proxy"
        @Suppress("DEPRECATION")
        val perAppRules = intent?.getSerializableExtra("perAppRules") as? HashMap<String, String>
            ?: hashMapOf()
        val policy = AppUidPolicy.build(installedApps.associate { it.packageName to it.uid }, android.os.Process.myUid(), perAppEnabled, perAppDefaultRule, perAppRules)
        uidPolicy = policy
        if (policy.blocking && Build.VERSION.SDK_INT < 29) {
            MainActivity.sendNativeLog("TUN", "Блокировка приложений требует Android 10 или новее")
            stopVpn(); return START_NOT_STICKY
        }
        runCatching { T2swrapper.setAppPolicy(policy.bridgeJson()) }.onFailure {
            MainActivity.sendNativeLog("TUN", "Не удалось применить UID-политику: ${it.message}")
            stopVpn(); return START_NOT_STICKY
        }
        appUidPackages = installedApps.filter { policy.actions[it.uid] != "direct" }
            .groupBy { it.uid }.mapValues { (_, apps) -> apps.first().packageName }
        trafficSessionStartedAt = System.currentTimeMillis()

        startForegroundService()
        publishState()
        startVpn()

        return START_NOT_STICKY
    }

    private fun startForegroundService(startStats: Boolean = true) {
        val notification = buildNotification(lastSpeed, lastPing)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        if (!startStats) return
        statsJob?.cancel()
        statsJob = serviceScope.launch(Dispatchers.IO) {
            var lastRx = 0L
            var lastTx = 0L
            var lastSampleAt = SystemClock.elapsedRealtime()

            while (isActive) {
                delay(2000)
                if (vpnStatus == "connected" && !MainActivity.isNativeCoreRunning()) {
                    withContext(Dispatchers.Main) { stopVpn() }
                    return@launch
                }
                val traffic = org.json.JSONObject(T2swrapper.trafficSnapshot())
                val currentRx = traffic.optLong("download")
                val currentTx = traffic.optLong("upload")

                val sampledAt = SystemClock.elapsedRealtime()
                val sampleDuration = (sampledAt - lastSampleAt).coerceAtLeast(1L)
                val rxSpeed = (currentRx - lastRx).coerceAtLeast(0L) * 1000L / sampleDuration
                val txSpeed = (currentTx - lastTx).coerceAtLeast(0L) * 1000L / sampleDuration
                lastSampleAt = sampledAt

                lastSpeed = "D: ${formatSpeedInternal(rxSpeed)} | U: ${formatSpeedInternal(txSpeed)}"
                lastRx = currentRx
                lastTx = currentTx

                val rxBytes = currentRx
                val txBytes = currentTx

                if (!paused && System.currentTimeMillis() % 10000 < 2000) {
                    lastPing = getPing()
                }

                val networkType = getUnderlyingNetworkType()
                val wifi = networkType == "wifi"
                val mobile = networkType == "mobile"
                val appBytes = perAppTraffic(traffic)
                VpnTrafficJournal.record(this@VpnTunnelService, trafficSessionId, rxBytes, txBytes, appBytes, networkType)

                ensureActive()
                if (stopping || !isAlive) return@launch
                updateNotification(lastSpeed, lastPing)
                MainActivity.sendVpnState(snapshot())
                MainActivity.sendNativeStats(
                    lastSpeed,
                    lastPing,
                    rxBytes,
                    txBytes,
                    isWifi = wifi,
                    isMobile = mobile,
                    sessionId = trafficSessionId,
                    appBytes = appBytes
                )
            }
        }
    }

    private fun perAppTraffic(traffic: org.json.JSONObject): Map<String, Long> {
        val apps = traffic.optJSONObject("apps") ?: return emptyMap()
        val result = mutableMapOf<String, Long>()
        apps.keys().forEach { uid ->
            val name = appUidPackages[uid.toIntOrNull()] ?: "nextlink.unknown"
            result[name] = (result[name] ?: 0L) + apps.optLong(uid)
        }
        return result
    }

    private fun checkpointTraffic() {
        if (trafficSessionId.isBlank()) return
        val traffic = org.json.JSONObject(T2swrapper.trafficSnapshot())
        VpnTrafficJournal.record(this, trafficSessionId, traffic.optLong("download"), traffic.optLong("upload"),
            perAppTraffic(traffic), getUnderlyingNetworkType())
    }

    private fun getUnderlyingNetworkType(): String {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return "unknown"
        val networks = manager.allNetworks.mapNotNull { network ->
            val caps = manager.getNetworkCapabilities(network) ?: return@mapNotNull null
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                manager.getNetworkInfo(network)?.isConnected != true
            ) return@mapNotNull null
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                else -> null
            }
        }
        return networks.firstOrNull() ?: "unknown"
    }

    private fun formatSpeedInternal(bytesPerSec: Long): String {
        return when {
            bytesPerSec >= 1024 * 1024 -> String.format(Locale.US, "%.1f MB/s", bytesPerSec.toDouble() / (1024 * 1024))
            bytesPerSec >= 1024 -> String.format(Locale.US, "%d KB/s", bytesPerSec / 1024)
            else -> "$bytesPerSec B/s"
        }
    }

    private suspend fun getPing(): String = withContext(Dispatchers.IO) {
        try {
            val process = Runtime.getRuntime().exec("ping -c 1 -W 2 8.8.8.8")
            val exitCode = process.waitFor()
            if (exitCode == 0) {
                val output = process.inputStream.bufferedReader().readText()
                val match = Regex("time=([\\d.]+)").find(output)
                match?.groupValues?.get(1)?.let { "${it.substringBefore(".")}ms" } ?: "N/A"
            } else {
                "Timeout"
            }
        } catch (e: Exception) {
            "Error"
        }
    }

    private fun updateNotification(speed: String, ping: String) {
        if (stopping || !isAlive) return
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildNotification(speed, ping))
    }

    private fun buildNotification(speed: String, ping: String): Notification {
        val stopIntent = Intent(this, VpnTunnelService::class.java).apply { action = ACTION_STOP }
        val pendingStop = PendingIntent.getService(this, 0, stopIntent, PendingIntent.FLAG_IMMUTABLE)

        val pingIntent = Intent(this, VpnTunnelService::class.java).apply { action = ACTION_PING }
        val pendingPing = PendingIntent.getService(this, 1, pingIntent, PendingIntent.FLAG_IMMUTABLE)

        val pauseIntent = Intent(this, VpnTunnelService::class.java).apply {
            action = if (paused) ACTION_RESUME else ACTION_PAUSE
        }
        val pendingPause = PendingIntent.getService(
            this, 2, pauseIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val mainIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingMain = PendingIntent.getActivity(
            this,
            0,
            mainIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setGroup(NotificationGroupPolicy.VPN)
            .setContentTitle(serverName)
            .setStyle(NotificationCompat.BigTextStyle().bigText(
                if (paused) NativeStrings.text(this, "VPN приостановлен") else if (vpnStatus == "starting") NativeStrings.text(this, "Подключение…") else NativeStrings.text(this, "Скорость: {0}", speed) + "\n" + NativeStrings.text(this, "Пинг: {0}", ping)
            ))
            .setSmallIcon(R.drawable.ic_notification_nl).addExtras(NotificationGroupPolicy.iconExtras(this))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingMain)
            .addAction(
                if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                NativeStrings.text(this, if (paused) "Продолжить" else "Пауза"),
                pendingPause,
            )
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, NativeStrings.text(this, "Отключить"), pendingStop)
            .addAction(android.R.drawable.ic_menu_mylocation, NativeStrings.text(this, "Пинг"), pendingPing)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VPN Status",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startVpn() {
        if (vpnInterface != null) return

        val intent = lastIntent
        val tunMtu = intent?.getIntExtra("tunMtu", 1500) ?: 1500
        val strictMode = intent?.getBooleanExtra("strictMode", true) ?: true
        val socksPort = intent?.getIntExtra("socksPort", 10808) ?: 10808

        val builder = Builder()
        if (!strictMode) builder.allowBypass()
        val ipv6Enabled = intent?.getBooleanExtra("ipv6", false) ?: false

        builder.setMtu(tunMtu)
        builder.addAddress("172.19.0.1", 24)

        // 1. НАДЕЖНЫЙ РОУТИНГ IPv4
        if (uidPolicy?.capturesTraffic != false) builder.addRoute("0.0.0.0", 0)

        // LAN bypass: исключаем локальные подсети из TUN.
        val bypassLan = intent?.getBooleanExtra("bypassLan", false) ?: false

        if (bypassLan &&
            Build.VERSION.SDK_INT >= 33 &&
            uidPolicy?.capturesTraffic != false) {

            listOf(
                "10.0.0.0/8",
                "172.16.0.0/12",
                "192.168.0.0/16",
                "169.254.0.0/16"
            ).forEach {
                val parts = it.split("/")
                builder.excludeRoute(
                    IpPrefix(
                        java.net.InetAddress.getByName(parts[0]),
                        parts[1].toInt()
                    )
                )
            }
        }

        builder.addDnsServer("8.8.8.8")
        builder.addDnsServer("1.1.1.1")

        // =======================================================
        // 🔥 ВОТ ЭТИ ДВЕ ВЕЩИ ИСПРАВЯТ ТВОЮ ПРОБЛЕМУ С TCP 🔥
        // =======================================================

        // Чиним краш Per-App проксирования (Direct / Proxy режимы)
        val perAppEnabled = intent?.getBooleanExtra("perAppEnabled", false) ?: false

        // 2. БЛОКИРОВКА УТЕЧКИ В 4G/Wi-Fi
        // Для глобального VPN скрываем оригинальную сеть. При Per-App проксировании НЕ форсируем null,
        // чтобы исключенные приложения (например Ozon) видели реальную Wi-Fi/Cellular сеть и не детектили VPN.
        if (!perAppEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            builder.setUnderlyingNetworks(null)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        // 3. ПРИНУДИТЕЛЬНЫЙ ПЕРЕХВАТ IPv6
        if (ipv6Enabled) {
            try {
                builder.addAddress("fdfe:dcba:9876::1", 126)
                if (uidPolicy?.capturesTraffic != false) builder.addRoute("::", 0)

                if (bypassLan &&
                    Build.VERSION.SDK_INT >= 33 &&
                    uidPolicy?.capturesTraffic != false) {

                    listOf(
                        "fc00::/7",
                        "fe80::/10"
                    ).forEach {
                        val parts = it.split("/")
                builder.excludeRoute(
                    IpPrefix(
                        java.net.InetAddress.getByName(parts[0]),
                        parts[1].toInt()
                    )
                )
                    }
                }
            } catch (e: Exception) {
                Log.e("VpnTunnelService", "IPv6 route error: ${e.message}")
            }
        }

        val policy = uidPolicy
        if (perAppEnabled && policy != null && policy.whitelist) {
            // An empty allow-list means "all apps" to Android. For all-Direct,
            // keep a placeholder UID and no default TUN routes instead.
            val packages = policy.allowedPackages.ifEmpty { setOf(this.packageName) }
            for (pkg in packages) runCatching { builder.addAllowedApplication(pkg) }
        } else {
            runCatching { builder.addDisallowedApplication(this.packageName) }
            for (pkg in policy?.directPackages.orEmpty()) runCatching { builder.addDisallowedApplication(pkg) }
        }

        try {
            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                stopVpn()
                return
            }
            // Publish connected only once the bridge has started.

            trafficSessionStartedAt = System.currentTimeMillis()

            val fdInt = vpnInterface!!.fd
            val startThread = Thread({
                try {
                    Thread.sleep(2000)

                    // 2. ИСПРАВЛЯЕМ TUN2SOCKS
                    // Добавляем параметр, который отключает IPv6 на уровне самого tun2socks,
                    // если он отключен в UI. Это спасет от SocketException!
                    val t2sConfig = "socks5://127.0.0.1:$socksPort"

                    // Если у тебя в t2swrapper есть параметр для отключения IPv6, передай его сюда.
                    // Если нет - ничего страшного, отключения в builder'е обычно хватает для ТГ.
                    synchronized(tunnelLifecycleLock) {
                        val tunDescriptor = vpnInterface
                        if (stopping || tunDescriptor?.fd != fdInt) return@synchronized
                        // tun2socks closes the descriptor when it stops. Transfer
                        // ownership explicitly so Android's ParcelFileDescriptor
                        // finalizer will not close the same fd a second time.
                        val ownedFd = tunDescriptor.detachFd()
                        vpnInterface = null
                        try {
                            T2swrapper.startVpn(ownedFd, t2sConfig)
                        } catch (error: Throwable) {
                            runCatching { ParcelFileDescriptor.adoptFd(ownedFd).close() }
                            throw error
                        }
                        tun2SocksStarted = true
                        hasActiveTunnel = true
                        connectedAtElapsed = SystemClock.elapsedRealtime()
                        vpnStatus = "connected"
                        publishState()
                    }
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                } catch (error: Throwable) {
                    Log.e("VpnTunnelService", "Failed to start TUN bridge", error)
                    MainActivity.sendNativeLog("TUN", "Failed to start TUN bridge: ${error.message}")
                    stopVpn()
                } finally {
                    synchronized(tunnelLifecycleLock) {
                        if (tunnelStartThread === Thread.currentThread()) {
                            tunnelStartThread = null
                        }
                    }
                }
            }, "NextLink-Tun2Socks-start")
            synchronized(tunnelLifecycleLock) {
                tunnelStartThread = startThread
                startThread.start()
            }
        } catch (e: Exception) {
            MainActivity.sendNativeLog("TUN", "Unable to establish VPN: ${e.message}")
            stopVpn()
        }
    }

    private fun pauseTunnel() {
        if (!isAlive || paused) return
        synchronized(tunnelLifecycleLock) {
            tunnelStartThread?.interrupt()
            tunnelStartThread = null
            if (tun2SocksStarted) {
                runCatching { T2swrapper.stopVpn() }
                    .onFailure { Log.e("VpnTunnelService", "Failed to pause TUN bridge", it) }
                tun2SocksStarted = false
            }
            runCatching { vpnInterface?.close() }
            vpnInterface = null
            if (vpnStatus == "connected") {
                elapsedBeforePause += (SystemClock.elapsedRealtime() - connectedAtElapsed).coerceAtLeast(0L)
            }
            vpnStatus = "paused"
            paused = true
            isPaused = true
            hasActiveTunnel = false
        }
        updateNotification(lastSpeed, lastPing)
        refreshQuickTile()
        publishState()
    }

    private fun resumeTunnel() {
        if (!isAlive || !paused) return
        paused = false
        isPaused = false
        vpnStatus = "starting"
        publishState()
        startVpn()
        updateNotification(lastSpeed, lastPing)
        refreshQuickTile()

    }

    private fun refreshQuickTile() {
        NextLinkTileService.refreshState()
    }

    private fun stopVpn() {
        val shouldStop = synchronized(tunnelLifecycleLock) {
            if (stopping) {
                false
            } else {
                stopping = true
                paused = false
                isPaused = false
                hasActiveTunnel = false
                tunnelStartThread?.interrupt()
                tunnelStartThread = null
                statsJob?.cancel()
                serviceScope.cancel()
                checkpointTraffic()
                if (tun2SocksStarted) {
                    try {
                        T2swrapper.stopVpn()
                    } catch (error: Exception) {
                        Log.e("VpnTunnelService", "Failed to stop TUN bridge", error)
                    }
                    tun2SocksStarted = false
                }
                checkpointTraffic()
                try {
                    vpnInterface?.close()
                } catch (error: Exception) {
                    Log.e("VpnTunnelService", "Error closing interface", error)
                }
                vpnInterface = null
                T2swrapper.setOwnerResolver(null)
                T2swrapper.setAppPolicy("")
                true
            }
        }
        if (!shouldStop) return

        vpnStatus = "stopped"
        isAlive = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        publishState()
        MainActivity.stopNativeCore()
        stopSelf()
        MainActivity.sendNativeLog("TUN", "VPN Stopped")
    }

    override fun onDestroy() {
        stopVpn()
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onRevoke() {
        MainActivity.sendNativeLog("TUN", "VPN permission was revoked by Android")
        stopVpn()
        super.onRevoke()
    }
}
