package pro.kaleert.nextlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.net.VpnService
import android.os.Build
import org.json.JSONObject

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED && intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        val preferences = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        val settingsJson = preferences.getString("flutter.app_settings", null)
        val autoStart = try {
            settingsJson?.let { JSONObject(it).optBoolean("autoStart", false) } == true
        } catch (_: Exception) {
            false
        }
        runCatching { SubscriptionUpdateJob.schedule(context) }
            .onFailure { Log.e("BootReceiver", "Could not schedule subscription updates", it) }
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED || !autoStart || VpnService.prepare(context) != null) return
        val saved = context.getSharedPreferences("quick_tile_vpn", Context.MODE_PRIVATE)
        if (saved.getString("config", null).isNullOrBlank()) return

        try {
            val start = Intent(context, VpnTunnelService::class.java).apply {
                action = VpnTunnelService.ACTION_START_SAVED
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(start)
            else context.startService(start)
        } catch (error: Exception) {
            Log.e("BootReceiver", "Could not restore VPN after boot", error)
        }
    }
}
