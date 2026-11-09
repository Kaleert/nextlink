package pro.kaleert.nextlink

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Persisted system job; shares the subscription parser with the foreground app. */
class SubscriptionUpdateJob : JobService() {
    companion object {
        const val ID = 2104
        private var runningJob: SubscriptionUpdateJob? = null
        fun onUiAttached() {
            // Do not let a headless parser overwrite edits in a newly opened UI.
            // JobScheduler retries against the foreground engine once it is ready.
            runningJob?.takeIf { it.engine != null }?.finish(true)
        }
        private fun settings(context: Context): JSONObject = runCatching {
            JSONObject(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.app_settings", "{}") ?: "{}")
        }.getOrDefault(JSONObject())

        fun schedule(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
            val config = settings(context)
            if (!config.optBoolean("autoUpdateSubs")) { scheduler.cancel(ID); return }
            val interval = config.optInt("subUpdateIntervalHours", 1).coerceIn(1, 168) * 3600000L
            val flex = (interval / 10).coerceIn(JobInfo.getMinFlexMillis(), 15 * 60000L)
            val existing = scheduler.getPendingJob(ID)
            if (existing != null && existing.intervalMillis == interval && existing.flexMillis == flex && existing.extras.getInt("scheduleVersion", 0) == 2) return
            val builder = JobInfo.Builder(ID, ComponentName(context, SubscriptionUpdateJob::class.java))
                .setPeriodic(interval, flex).setPersisted(true)
                .setExtras(PersistableBundle().apply { putInt("scheduleVersion", 2) })
                .setBackoffCriteria(30000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
            if (Build.VERSION.SDK_INT >= 28) {
                // NextLink is excluded from its own TUN. NETWORK_TYPE_ANY may
                // select that VPN and leave CONNECTIVITY unsatisfied forever.
                builder.setRequiredNetwork(NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build())
            } else builder.setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            val result = scheduler.schedule(builder.build())
            if (result != JobScheduler.RESULT_SUCCESS) Log.e("SubscriptionUpdateJob", "Could not schedule update job")

        }

        fun notifyUpdated(context: Context, count: Int) {
            if (count <= 0 || !settings(context).optBoolean("notifySubUpdate")) return
            NotificationGroupPolicy.migrate(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel("subscription_updates", NativeStrings.text(context, "Обновления подписок"), NotificationManager.IMPORTANCE_LOW))
            val open = PendingIntent.getActivity(context, 2105,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            runCatching { manager.notify(2105, NotificationCompat.Builder(context, "subscription_updates")
                .setGroup(NotificationGroupPolicy.SUBSCRIPTIONS).setSmallIcon(R.drawable.ic_notification_nl).addExtras(NotificationGroupPolicy.iconExtras(context)).setContentTitle(NativeStrings.text(context, "Подписки обновлены"))
                .setContentText(NativeStrings.text(context, "Обновлено подписок: {0}", count)).setAutoCancel(true).setContentIntent(open).build()) }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var current: JobParameters? = null
    private val timeout = Runnable { finish(true) }

    override fun onStartJob(params: JobParameters): Boolean {
        if (!settings(this).optBoolean("autoUpdateSubs")) return false
        current = params
        runningJob = this
        handler.postDelayed(timeout, 240000)
        val retryIds=org.json.JSONArray(getSharedPreferences("subscription_retry", MODE_PRIVATE).getString("ids", "[]"))
        val retryPreferences = getSharedPreferences("subscription_retry", MODE_PRIVATE)
        val interval = settings(this).optInt("subUpdateIntervalHours", 1).coerceIn(1, 168) * 3600000L
        val now = System.currentTimeMillis()
        val fullDue = now - retryPreferences.getLong("lastFullAttempt", 0L) >= interval
        val ids = if(fullDue) emptyList() else (0 until retryIds.length()).map { retryIds.getString(it) }
        if(ids.isEmpty()) retryPreferences.edit().putLong("lastFullAttempt", now).apply()
        getSharedPreferences("subscription_job_status", MODE_PRIVATE).edit().putLong("startedAt", now).putString("stage", "starting").apply()
        if (MainActivity.updateSubscriptionsInExistingEngine(ids) { report ->
            if (current === params) complete(report)
        }) {
            Log.i("SubscriptionUpdateJob", "Updating through UI engine")
            return true
        }
        Log.i("SubscriptionUpdateJob", "Updating through headless engine")
        try {
            val flutter = FlutterEngine(applicationContext)
            engine = flutter
            MethodChannel(flutter.dartExecutor.binaryMessenger, "pro.kaleert.nextlink/subscription_worker")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "retryIds" -> result.success(ids)
                        "complete" -> {
                            result.success(null)
                            handler.post {
                                if (engine === flutter && current === params)
                                    complete(call.arguments as? Map<*, *>)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            MethodChannel(flutter.dartExecutor.binaryMessenger, "pro.kaleert.nextlink/vpn")
                .setMethodCallHandler { call, result ->
                    if(call.method == "scheduleSubscriptionUpdates") {
                        schedule(this); result.success(null)
                    } else if (call.method == "notifySubscriptionUpdated") {
                        notifyUpdated(this, call.argument<Int>("count") ?: 0); result.success(null)
                    } else if(call.method == "storeAutomationPlan") {
                        try { AutomationService.store(this, call.argument<String>("plan") ?: "{}"); result.success(null) }
                        catch(error: Exception) { result.error("AUTOMATION_PLAN_FAILED", error.message, null) }
                    } else if(call.method == "getAwgCorePath") {
                        val downloaded=java.io.File(filesDir,"libawg.so")
                        val file=downloaded
                        if(file.isFile) result.success(file.absolutePath) else result.error("AWG_CORE_MISSING", "AWG core is missing", null)
                    } else result.notImplemented()
                }
            val loader = io.flutter.FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            flutter.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(), "subscriptionUpdateMain"))
        } catch (error: Exception) {
            Log.e("SubscriptionUpdateJob", "Background update failed", error)
            handler.post { finish(true) }
        }
        return true
    }

    private fun complete(report: Map<*, *>?) {
        val success = report?.get("success") == true
        val updated = (report?.get("updatedIds") as? List<*>)?.size ?: 0
        getSharedPreferences("subscription_job_status", MODE_PRIVATE).edit()
            .putLong("finishedAt", System.currentTimeMillis()).putBoolean("success", success)
            .putInt("updatedCount", updated).putString("stage", if(success) "complete" else "retry").apply()
        Log.i("SubscriptionUpdateJob", "Finished: success=$success updated=$updated")
        val failed=report?.get("failedIds") as? List<*>
        if(failed != null) getSharedPreferences("subscription_retry", MODE_PRIVATE).edit()
            .putString("ids", org.json.JSONArray(failed).toString()).commit()
        finish(report?.get("success") != true)
    }

    private fun release() {
        if (runningJob === this) runningJob = null
        handler.removeCallbacks(timeout)
        val old = engine; engine = null
        old?.destroy()
    }
    private fun finish(retry: Boolean) {
        val params = current ?: return
        current = null
        release()
        jobFinished(params, retry)
    }
    override fun onStopJob(params: JobParameters): Boolean {
        current = null
        release()
        return true
    }
    override fun onDestroy() { current = null; release(); super.onDestroy() }
}
