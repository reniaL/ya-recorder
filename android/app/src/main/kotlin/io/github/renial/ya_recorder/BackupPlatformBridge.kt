package io.github.renial.ya_recorder

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class BackupPlatformBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "io.github.renial.ya_recorder/backup_commands")
    private val main = Handler(Looper.getMainLooper())
    private val metadataWorker = Executors.newSingleThreadExecutor()
    private var picker: MethodChannel.Result? = null
    private var disposed = false
    private val runtime get() = BackupTaskRuntime.get(activity)

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickSource", "pickTarget" -> {
                    check(picker == null) { "picker-busy" }
                    check(!activity.isFinishing && activity.hasWindowFocus()) { "foreground-required" }
                    val target = call.method == "pickTarget"
                    val intent = Intent(if (target) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE).setType("application/zip")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    if (target) {
                        intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        intent.putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "backup.zip")
                    }
                    picker = result
                    try { activity.startActivityForResult(intent, PICKER) }
                    catch (error: Exception) { picker = null; throw error }
                }
                "prepare" -> result.success(runtime.prepare(requireNotNull(call.argument<String>("uri")), requireNotNull(call.argument<String>("direction"))))
                "snapshot" -> result.success(runtime.snapshot())
                "startCopy" -> {
                    check(activity.hasWindowFocus() && !activity.isFinishing) { "foreground-required" }
                    val id = requireNotNull(call.argument<String>("taskId"))
                    runtime.reserve(id, requireNotNull(call.argument<String>("direction")), requireNotNull(call.argument<String>("uri")))
                    try {
                        val intent = Intent(activity, BackupTaskService::class.java).putExtra("taskId", id)
                        if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent) else activity.startService(intent)
                    } catch (_: Exception) { runtime.startFailed(id) }
                    val processRuntime = runtime
                    main.postDelayed({ processRuntime.expireUnstarted(id) }, 10_000)
                    result.success(runtime.snapshot())
                }
                "cancel" -> { runtime.cancel(requireNotNull(call.argument<String>("taskId"))); result.success(null) }
                "accept" -> { runtime.accept(requireNotNull(call.argument<String>("taskId"))); result.success(null) }
                "release" -> runtime.release(requireNotNull(call.argument<String>("taskId"))) { error ->
                    main.post { if (error == null) result.success(runtime.snapshot()) else result.error("backup-cleanup-failed", error.message, null) }
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) { result.error("backup-platform-failed", error.message, null) }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICKER) return false
        val pending = picker ?: return true
        picker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { pending.success(null); return true }
        metadataWorker.execute {
            try {
                require(uri.scheme == "content") { "document-uri-required" }
                val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                try { activity.contentResolver.takePersistableUriPermission(uri, flags) } catch (_: SecurityException) { /* Session grant still works. */ }
                var name: String? = null
                activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) name = it.getString(0)
                }
                val value = mapOf("uri" to uri.toString(), "displayName" to (name ?: uri.lastPathSegment ?: "backup.zip"))
                main.post { if (!disposed) pending.success(value) }
            } catch (error: Exception) { main.post { if (!disposed) pending.error("backup-document-failed", error.message, null) } }
        }
        return true
    }

    fun dispose() {
        disposed = true
        picker?.error("backup-picker-detached", "Activity detached; choose again", null)
        picker = null
        channel.setMethodCallHandler(null)
        metadataWorker.shutdown()
    }

    companion object { private const val PICKER = 8102 }
}
