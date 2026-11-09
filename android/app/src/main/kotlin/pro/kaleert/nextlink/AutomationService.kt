package pro.kaleert.nextlink

import android.app.*
import android.content.*
import android.net.*
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy

/** Foreground automation survives Flutter engine teardown and owns all Android triggers. */
class AutomationService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var previousNetwork: String? = null
    private var previousHotspot = false
    private val timerAt = mutableMapOf<String, Long>()
    private var lastProbe = 0L
    private var failures = 0
    private var planVersion = ""
    private val profileSignatures = mutableMapOf<String, String>()
    private var hadTargets = false
    private val networkEvents = Channel<Unit>(Channel.CONFLATED)
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { networkEvents.trySend(Unit) }
        override fun onLost(network: Network) { networkEvents.trySend(Unit) }
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) { networkEvents.trySend(Unit) }
    }
    override fun onBind(intent: Intent?) = null

    companion object {
        const val PREFS = "nextlink_automation"
        fun history(context: Context): JSONArray = runCatching {
            JSONArray(context.getSharedPreferences(PREFS, MODE_PRIVATE).getString("history", "[]"))
        }.getOrDefault(JSONArray())
        @Synchronized fun record(context: Context, profile: String, reason: String, server: String, result: String) {
            val old = history(context)
            val rows = JSONArray().put(JSONObject().put("time", System.currentTimeMillis()).put("profile", profile).put("reason", reason).put("server", server).put("result", result))
            for (i in 0 until minOf(old.length(), 199)) rows.put(old.get(i))
            context.getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("history", rows.toString()).apply()
        }
        fun store(context: Context, plan: String) {
            val data = JSONObject(plan)
            require(data.optJSONArray("profiles") != null && data.optJSONArray("servers") != null)
            check(context.getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("plan", plan).commit())
        }
        fun sync(context: Context, plan: String) {
            store(context, plan)
            val profiles = JSONObject(plan).optJSONArray("profiles") ?: JSONArray()
            val enabled = (0 until profiles.length()).any { profiles.getJSONObject(it).optBoolean("isEnabled") }
            val intent = Intent(context, AutomationService::class.java)
            if (enabled) {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } else context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("automation", NativeStrings.text(this, "Автоматизация профилей"), NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 50, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        startForeground(102, NotificationCompat.Builder(this, "automation").setGroup(NotificationGroupPolicy.AUTOMATION).setSmallIcon(R.drawable.ic_notification_nl).addExtras(NotificationGroupPolicy.iconExtras(this))
            .setContentTitle(NativeStrings.text(this, "Профили NextLink")).setContentText(NativeStrings.text(this, "Отслеживание сети и условий переключения")).setContentIntent(open).setOngoing(true).setSilent(true).build())
        getSystemService(ConnectivityManager::class.java).registerNetworkCallback(NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), networkCallback)
        scope.launch {
            while (isActive) {
                try { evaluate() } catch (error: Exception) {
                    if (error is CancellationException) throw error
                    MainActivity.sendNativeLog("AUTOMATION", "Evaluation failed: ${error.javaClass.simpleName}")
                }
                withTimeoutOrNull(5000) { networkEvents.receive() }
            }
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY
    override fun onDestroy() { scope.cancel(); runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback) }; networkEvents.close(); super.onDestroy() }

    private fun environment(): Pair<String, Boolean> {
        val cm = getSystemService(ConnectivityManager::class.java)
        val caps = cm.allNetworks.mapNotNull { cm.getNetworkCapabilities(it) }.filter { !it.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) }
        val network = when {
            caps.any { it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } -> "wifi"
            caps.any { it.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } -> "mobile"
            caps.isNotEmpty() -> "other"
            else -> "none"
        }
        val hotspot = runCatching {
            val wifi = applicationContext.getSystemService(WIFI_SERVICE)
            wifi.javaClass.getMethod("isWifiApEnabled").invoke(wifi) == true
        }.getOrDefault(false)
        val hotspotInterface = runCatching {
            java.util.Collections.list(java.net.NetworkInterface.getNetworkInterfaces()).any {
                val name = it.name.lowercase()
                it.isUp && (name.startsWith("ap") || name.startsWith("softap") || name.startsWith("wlan1") || name.startsWith("swlan"))
            }
        }.getOrDefault(false)
        return network to (hotspot || hotspotInterface)
    }
    private fun trigger(profile: JSONObject, name: String): Boolean {
        val values = profile.optJSONArray("triggers") ?: JSONArray()
        return (0 until values.length()).any { values.optString(it) == name }
    }
    private fun objects(array: JSONArray?): List<JSONObject> = if (array == null) emptyList() else (0 until array.length()).map { array.getJSONObject(it) }

    private suspend fun evaluate() {
        val text = getSharedPreferences(PREFS, MODE_PRIVATE).getString("plan", "{}") ?: "{}"
        val plan = JSONObject(text)
        val profiles = objects(plan.optJSONArray("profiles")).filter { it.optBoolean("isEnabled") }
        if (profiles.isEmpty()) { stopSelf(); return }
        if (text != planVersion) {
            val ids = profiles.map { it.getString("id") }.toSet()
            val added = ids.any { it !in profileSignatures }
            timerAt.keys.retainAll(ids)
            profileSignatures.keys.retainAll(ids)
            for (profile in profiles) {
                val id = profile.getString("id")
                val signature = profile.toString()
                if (profileSignatures[id] != signature) timerAt.remove(id)
                profileSignatures[id] = signature
            }
            val hasTargets = (plan.optJSONArray("servers")?.length() ?: 0) > 0
            if (added || (!hadTargets && hasTargets)) previousNetwork = null
            hadTargets = hasTargets
            planVersion = text
        }
        val now = SystemClock.elapsedRealtime()
        val userStopAt = getSharedPreferences(PREFS, MODE_PRIVATE).getLong("userStopAt", 0L)
        val (network, hotspot) = environment()
        val old = previousNetwork
        val oldHotspot = previousHotspot
        previousNetwork = network
        previousHotspot = hotspot
        if (System.currentTimeMillis() - userStopAt < 10000) return
        if (VpnTunnelService.isPaused) { timerAt.clear(); return }
        if (VpnTunnelService.snapshot()["status"] == "starting") return
        val connected = VpnTunnelService.hasActiveTunnel
        if (!connected) timerAt.clear()
        var selected: JSONObject? = null
        var reason = ""
        for (profile in profiles) {
            val triggers = profile.optJSONArray("triggers") ?: JSONArray()
            val matched = AutomationPolicy.networkTrigger((0 until triggers.length()).map { triggers.getString(it) }.toSet(), network, old, hotspot, oldHotspot)
            if (matched.isNotEmpty()) { selected = profile; reason = matched; break }
            if (connected && trigger(profile, "timer")) {
                val id = profile.getString("id")
                val since = timerAt.getOrPut(id) { now }
                if (now - since >= profile.optLong("intervalMinutes", 30).coerceIn(1, 1440) * 60000) { selected = profile; reason = "timer"; break }
            }
        }
        if (selected == null && connected && network != "none" && profiles.any { trigger(it, "timeout") } && now - lastProbe >= 30000) {
            lastProbe = now
            failures = if (probe(plan)) 0 else failures + 1
            if (failures >= 2) { selected = profiles.first { trigger(it, "timeout") }; reason = "timeout"; failures = 0 }
        }
        val profile = selected ?: return
        timerAt[profile.getString("id")] = now
        val servers = objects(plan.optJSONArray("servers"))
        val pinned = profile.optString("serverKey").takeUnless { it == "null" || it.isBlank() }
        val keys = profile.optJSONArray("serverKeys") ?: JSONArray()
        val group = (0 until keys.length()).map { keys.getString(it) }.toSet()
        val saved = getSharedPreferences("quick_tile_vpn", MODE_PRIVATE)
        val activeKey = saved.getString("serverKey", "")
        val targetKey = AutomationPolicy.target(servers.map { it.optString("key") }, group, pinned, activeKey, reason == "timeout")
        val target = servers.firstOrNull { it.optString("key") == targetKey }
        if (target == null) { record(this, profile.optString("name"), reason, "", "Нет доступных конфигураций"); return }
        if (connected && target.optString("key") == activeKey && reason != "timeout") return
        if (VpnService.prepare(this) != null) { record(this, profile.optString("name"), reason, target.optString("name"), "Требуется разрешение VPN в приложении"); return }
        val previous = servers.firstOrNull { it.optString("key") == activeKey }
        currentCoroutineContext().ensureActive()
        if (getSharedPreferences(PREFS, MODE_PRIVATE).getLong("userStopAt", 0L) != userStopAt) return
        apply(target, plan)
        var ready = false
        for (attempt in 0 until 20) {
            delay(500)
            if (getSharedPreferences(PREFS, MODE_PRIVATE).getLong("userStopAt", 0L) != userStopAt) return
            if (VpnTunnelService.hasActiveTunnel && MainActivity.isNativeCoreRunning()) { ready = true; break }
        }
        val success = ready && probe(plan)
        currentCoroutineContext().ensureActive()
        if (getSharedPreferences(PREFS, MODE_PRIVATE).getLong("userStopAt", 0L) != userStopAt) return
        record(this, profile.optString("name"), reason, target.optString("name"), if (success) "Подключено" else "Сервер недоступен")
        if (!success && previous != null && previous !== target) {
            apply(previous, plan)
            record(this, profile.optString("name"), "rollback", previous.optString("name"), "Возврат к предыдущему серверу")
        }
    }

    private fun apply(target: JSONObject, plan: JSONObject) {
        val intent = Intent(this, VpnTunnelService::class.java).setAction(VpnTunnelService.ACTION_AUTOMATION)
            .putExtra("automationTarget", target.toString()).putExtra("automationTunnel", plan.optJSONObject("tunnel")?.toString() ?: "{}")
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }
    private suspend fun probe(plan: JSONObject): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val port = plan.optJSONObject("tunnel")?.optInt("httpPort", 10809) ?: 10809
            val url = java.net.URL(plan.optString("probeUrl", "https://www.gstatic.com/generate_204"))
            val conn = url.openConnection(Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", port))) as HttpURLConnection
            try { conn.connectTimeout = 4000; conn.readTimeout = 4000; conn.instanceFollowRedirects = true; conn.responseCode in 200..399 } finally { conn.disconnect() }
        }.getOrDefault(false)
    }
}

class AutomationBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val plan = context.getSharedPreferences(AutomationService.PREFS, Context.MODE_PRIVATE).getString("plan", null) ?: return
        runCatching { AutomationService.sync(context, plan) }
    }
}
