package pro.kaleert.nextlink

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Icon

/** Explicit groups keep OEM automatic summaries from duplicating the VPN row. */
object NotificationGroupPolicy {
    const val VPN = "nextlink.vpn"
    const val SUBSCRIPTIONS = "nextlink.subscriptions"
    const val AUTOMATION = "nextlink.automation"
    private var miuiIcon: Icon? = null

    // MIUI's collapsed row reads miui.appIcon instead of Notification.smallIcon.
    // Supply the current launcher artwork as a bitmap, bypassing its stale app cache.
    fun iconExtras(context: Context): Bundle {
        val icon = miuiIcon ?: run {
            val artwork = context.getDrawable(R.mipmap.ic_launcher)!!
            val bitmap = Bitmap.createBitmap(192, 192, Bitmap.Config.ARGB_8888)
            artwork.setBounds(0, 0, 192, 192)
            artwork.draw(Canvas(bitmap))
            Icon.createWithBitmap(bitmap).also { miuiIcon = it }
        }
        return Bundle().apply { putParcelable("miui.appIcon", icon) }
    }

    fun migrate(context: Context) {
        if (Build.VERSION.SDK_INT < 24) return
        val manager = context.getSystemService(NotificationManager::class.java)
        runCatching {
            val records = manager.activeNotifications
            for (record in records) {
                if (record.tag == "ranker_group") continue
                val group = when (record.id) {
                    101 -> VPN
                    102 -> AUTOMATION
                    2105 -> SUBSCRIPTIONS
                    else -> "nextlink.downloads"
                }
                if (record.notification.group != group ||
                    record.notification.smallIcon?.resId != R.drawable.ic_notification_nl ||
                    record.notification.getLargeIcon() != null ||
                    !record.notification.extras.containsKey("miui.appIcon")) {
                    val updated = Notification.Builder.recoverBuilder(context, record.notification)
                        .setGroup(group).setGroupSummary(false).setOnlyAlertOnce(true)
                        .setSmallIcon(R.drawable.ic_notification_nl)
                        .addExtras(iconExtras(context))
                        .setLargeIcon(null as android.graphics.Bitmap?).build().apply {
                            extras.remove(Notification.EXTRA_LARGE_ICON)
                            extras.remove(Notification.EXTRA_LARGE_ICON_BIG)
                        }
                    manager.notify(record.tag, record.id, updated)
                }
            }
            for (record in records) {
                if (record.tag == "ranker_group" && record.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0)
                    manager.cancel(record.tag, record.id)
            }
        }
    }
}
