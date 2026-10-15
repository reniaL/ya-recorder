package io.github.renial.ya_recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.net.Uri

/** Owns real streaming work, not an empty foreground lifetime around Activity IO. */
class BackupTaskService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private var taskId: String? = null
    private lateinit var runtime: BackupTaskRuntime

    override fun onCreate() {
        super.onCreate()
        runtime = BackupTaskRuntime.get(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra("taskId") ?: run { stopSelf(); return START_NOT_STICKY }
        if (intent.action == "cancel") {
            runtime.cancel(id)
            if (taskId == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (taskId != null) return START_NOT_STICKY
        val current = runtime.snapshot()
        if (current?.get("taskId") != id || current["status"] != "running") {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        taskId = id
        try {
            val notification = notification()
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(NOTIFICATION_ID, notification)
            runtime.onChanged = { main.post { if (taskId == id) refresh() } }
            runtime.execute(id) { main.post { finish() } }
            // Bound even on Android versions without onTimeout. A blocked provider
            // may delay cancellation until its current read/write returns.
            main.postDelayed({ runtime.cancel(id, "task-timeout") }, 30 * 60 * 1000L)
        } catch (_: Exception) {
            runtime.startFailed(id)
            finish()
        }
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val localized = AppLanguagePreferences.localizedContext(this)
        val manager = getSystemService(NotificationManager::class.java)
        val title = localized.getString(R.string.backup_notification_title)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(this, 81,
            Intent(this, MainActivity::class.java).putExtra("backupTaskId", taskId)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val cancel = PendingIntent.getService(this, 82,
            Intent(this, BackupTaskService::class.java).setAction("cancel")
                .setData(Uri.parse("ya-backup://cancel/$taskId")).putExtra("taskId", taskId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val snapshot = runtime.snapshot()
        val bytes = (snapshot?.get("processedBytes") as? Number)?.toLong() ?: 0
        val total = (snapshot?.get("totalBytes") as? Number)?.toLong() ?: 0
        val reading = snapshot?.get("direction") == "read"
        val text = when (snapshot?.get("stage")) {
            "preparing" -> R.string.backup_preparing
            "packing" -> R.string.backup_packing
            "verifying" -> R.string.backup_verifying
            else -> if (reading) R.string.backup_reading else R.string.backup_writing
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle(title)
            .setContentText(localized.getString(text, bytes / 1024))
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setProgress(if (total > 0) 1000 else 0, if (total > 0) ((bytes * 1000) / total).coerceIn(0, 1000).toInt() else 0, total <= 0)
            .addAction(Notification.Action.Builder(null, localized.getString(R.string.backup_cancel), cancel).build()).build()
    }

    private fun refresh() {
        try { getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification()) }
        catch (_: SecurityException) { /* Denied notifications do not stop the task. */ }
    }

    // Android 15+ dataSync time limit: stop promptly, keep cancellation/cleanup owned by worker.
    override fun onTimeout(startId: Int, fgsType: Int) {
        taskId?.let { runtime.cancel(it, "service-timeout") }
        finish()
    }

    private fun finish() {
        main.removeCallbacksAndMessages(null)
        taskId = null
        runtime.onChanged = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        runtime.serviceStopped()
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        runtime.onChanged = null
        taskId?.let { runtime.cancel(it, "service-destroyed") }
        runtime.serviceStopped()
        taskId = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL = "backup_tasks"
        private const val NOTIFICATION_ID = 81
    }
}
