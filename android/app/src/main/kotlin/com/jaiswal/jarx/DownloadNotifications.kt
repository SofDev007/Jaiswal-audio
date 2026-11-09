package com.jaiswal.jarx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build

// The download progress notification: one per playlist being downloaded
// ("Downloading Sune hue gaane · 12 of 26 · about 4 min left") and one for
// single songs, each with the song's cover, JARX's accent colour and a
// progress bar; it turns into a "downloaded" notification at the end.
// Silent (low importance, no sound or vibration). Dart drives it
// (download_notifier.dart).
object DownloadNotifications {
    private const val CHANNEL = "jarx_downloads"
    private const val ACCENT = 0xFFFE385E.toInt()

    private fun manager(ctx: Context) =
        ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val m = manager(ctx)
        if (m.getNotificationChannel(CHANNEL) != null) return
        m.createNotificationChannel(
            NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Progress of songs and playlists being downloaded"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
        )
    }

    private fun cover(path: String?): Bitmap? = try {
        if (path.isNullOrEmpty()) null else BitmapFactory.decodeFile(path)
    } catch (_: Throwable) {
        null
    }

    /** [max] 0 with [ongoing] = indeterminate bar; [done] = no bar. */
    fun show(
        ctx: Context, id: Int, title: String, text: String, sub: String?,
        progress: Int, max: Int, ongoing: Boolean, done: Boolean,
        coverPath: String?, timeoutMs: Long,
    ) {
        ensureChannel(ctx)
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = open?.let {
            PendingIntent.getActivity(
                ctx, 7001, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(ctx, CHANNEL)
        else
            @Suppress("DEPRECATION") Notification.Builder(ctx)
        b.setSmallIcon(R.drawable.ic_stat_jarx)
            .setColor(ACCENT)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setShowWhen(done)
            .setCategory(if (done) Notification.CATEGORY_STATUS else Notification.CATEGORY_PROGRESS)
        if (!sub.isNullOrEmpty()) b.setSubText(sub)
        if (tap != null) b.setContentIntent(tap)
        cover(coverPath)?.let { b.setLargeIcon(it) }
        if (!done) b.setProgress(max, progress, max == 0)
        if (timeoutMs > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) b.setTimeoutAfter(timeoutMs)
        try {
            manager(ctx).notify(id, b.build())
        } catch (_: SecurityException) {
            // Notifications not allowed: nothing to show.
        }
    }

    fun cancel(ctx: Context, id: Int) = manager(ctx).cancel(id)
}
