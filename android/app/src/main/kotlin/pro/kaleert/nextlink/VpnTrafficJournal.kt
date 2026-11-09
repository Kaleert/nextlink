package pro.kaleert.nextlink

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Durable cumulative checkpoints. Acknowledge only after Flutter has saved the delta. */
object VpnTrafficJournal {
    private const val PREFS = "vpn_traffic_journal"
    private var activeSession = ""
    private var bucket = ""
    private var segment = 0
    private var baseRx = 0L
    private var baseTx = 0L
    private var baseApps = emptyMap<String, Long>()
    private var lastRx = 0L
    private var lastTx = 0L
    private var lastApps = emptyMap<String, Long>()
    @Synchronized fun record(context: Context, session: String, rx: Long, tx: Long, apps: Map<String, Long>, network: String) {
        if (session.isBlank()) return
        val now = System.currentTimeMillis()
        val day = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date(now))
        val nextBucket = "$day/$network"
        if (activeSession != session) {
            activeSession = session; bucket = nextBucket; segment = 0
            baseRx = 0L; baseTx = 0L; baseApps = emptyMap()
        } else if (bucket != nextBucket) {
            bucket = nextBucket; segment++
            baseRx = lastRx; baseTx = lastTx; baseApps = lastApps
        }
        val key = "$session/$segment"
        val segmentApps = apps.mapValues { (name, bytes) -> (bytes - (baseApps[name] ?: 0L)).coerceAtLeast(0L) }
        lastRx = rx; lastTx = tx; lastApps = apps
        val prefs=context.getSharedPreferences(PREFS,Context.MODE_PRIVATE)
        val entries=JSONObject(prefs.getString("entries","{}") ?: "{}")
        entries.put(key,JSONObject().put("sessionId",key).put("rx",(rx-baseRx).coerceAtLeast(0L)).put("tx",(tx-baseTx).coerceAtLeast(0L))
            .put("appBytes",JSONObject(segmentApps)).put("network",network).put("timestamp",now))
        val keys=entries.keys().asSequence().toList()
        if(keys.size>512) keys.sortedBy { entries.getJSONObject(it).optLong("timestamp") }
            .take(keys.size-512).forEach { entries.remove(it) }
        prefs.edit().putString("entries",entries.toString()).apply()
    }
    @Synchronized fun pending(context: Context): String {
        val entries=JSONObject(context.getSharedPreferences(PREFS,Context.MODE_PRIVATE).getString("entries","{}") ?: "{}")
        return JSONArray(entries.keys().asSequence().map { entries.getJSONObject(it) }
            .sortedBy { it.optLong("timestamp") }.toList()).toString()
    }
    @Synchronized fun acknowledge(context: Context, session: String, rx: Long, tx: Long) {
        val prefs=context.getSharedPreferences(PREFS,Context.MODE_PRIVATE)
        val entries=JSONObject(prefs.getString("entries","{}") ?: "{}")
        val entry=entries.optJSONObject(session) ?: return
        // A newer checkpoint may have arrived while Dart was saving this one.
        if(entry.optLong("rx")<=rx && entry.optLong("tx")<=tx) {
            entries.remove(session)
            prefs.edit().putString("entries",entries.toString()).apply()
        }
    }
}
