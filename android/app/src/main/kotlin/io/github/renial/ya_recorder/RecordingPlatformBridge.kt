package io.github.renial.ya_recorder

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class RecordingPlatformBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val commands = MethodChannel(messenger, COMMAND_CHANNEL_NAME)
    private val events = EventChannel(messenger, EVENT_CHANNEL_NAME)

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var receiverRegistered = false
    private val persistenceCommands = SerialRecordingCommands()
    private val mainHandler = Handler(Looper.getMainLooper())

    private val eventReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val event = when (intent.action) {
                RecordingService.EVENT_STATE -> mapOf(
                    "type" to "state",
                    "state" to intent.getStringExtra(RecordingService.EXTRA_STATE),
                    "elapsedMs" to intent.getLongExtra(RecordingService.EXTRA_ELAPSED_MS, 0L),
                    "canResume" to intent.getBooleanExtra(RecordingService.EXTRA_CAN_RESUME, false),
                    "sessionId" to intent.getStringExtra(RecordingService.EXTRA_SESSION_ID),
                    "format" to intent.getStringExtra(RecordingService.EXTRA_FORMAT),
                )
                RecordingService.EVENT_FILE_READY -> mapOf(
                    "type" to "fileReady",
                    "recording" to mapOf(
                        "id" to intent.getStringExtra(RecordingService.EXTRA_ID),
                        "filePath" to intent.getStringExtra(RecordingService.EXTRA_FILE_PATH),
                        "createdAtMs" to intent.getLongExtra(RecordingService.EXTRA_CREATED_AT_MS, 0L),
                        "durationMs" to intent.getLongExtra(RecordingService.EXTRA_DURATION_MS, 0L),
                        "fileSizeBytes" to intent.getLongExtra(RecordingService.EXTRA_FILE_SIZE_BYTES, 0L),
                        "wasInterrupted" to intent.getBooleanExtra(RecordingService.EXTRA_WAS_INTERRUPTED, false),
                        "format" to intent.getStringExtra(RecordingService.EXTRA_FORMAT),
                    ),
                )
                RecordingService.EVENT_ERROR -> mapOf(
                    "type" to "error",
                    "code" to intent.getStringExtra(RecordingService.EXTRA_ERROR_CODE),
                    "message" to intent.getStringExtra(RecordingService.EXTRA_ERROR_MESSAGE),
                )
                else -> return
            }
            eventSink?.success(event)
        }
    }

    init {
        commands.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestMicrophonePermission" -> requestMicrophonePermission(result)
            "openAppSettings" -> openAppSettings(result)
            "getStatus" -> result.success(RecordingService.currentStatus())
            "start" -> startRecording(call, result)
            "pause" -> sendRecordingCommand(RecordingService.ACTION_PAUSE, result)
            "resume" -> sendRecordingCommand(RecordingService.ACTION_RESUME, result)
            "stop" -> sendRecordingCommand(RecordingService.ACTION_STOP, result)
            "cancel" -> sendRecordingCommand(RecordingService.ACTION_CANCEL, result)
            "recoverRecordings" -> persistenceCall(result) {
                val batch = AndroidRecordingPersistence.get(activity).recover()
                mapOf("recordings" to batch.recordings.map { it.toMap() }, "unresolvedCount" to batch.unresolvedIds.size)
            }
            "acknowledgeRecording", "deferRecording" -> persistenceCall(result) {
                val id = (call.arguments as? Map<*, *>)?.get("id") as? String
                    ?: throw IllegalArgumentException("Recording identity is required")
                RecordingFormat.M4A.completedFileName(id)
                try {
                    if (call.method == "acknowledgeRecording") AndroidRecordingPersistence.get(activity).acknowledge(id)
                } finally {
                    mainHandler.post {
                        if (RecordingService.currentStatus()["sessionId"] == id) {
                            try {
                                activity.startService(RecordingService.commandIntent(activity, RecordingService.ACTION_INDEX_FINISHED)
                                    .putExtra(RecordingService.EXTRA_ID, id))
                            } catch (error: Exception) {
                                Log.e("RecordingBridge", "Unable to finish foreground index wait", error)
                            }
                        }
                    }
                }
                null
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        registerEventReceiver()
        eventSink?.success(RecordingService.currentStatus().withEventType())
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        unregisterEventReceiver()
    }

    private fun persistenceCall(result: MethodChannel.Result, action: () -> Any?) {
        persistenceCommands.submit {
            try {
                val value = action()
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                mainHandler.post { result.error("recording-persistence-failed", error.message, null) }
            }
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != MICROPHONE_PERMISSION_REQUEST_CODE) {
            return false
        }

        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    fun dispose() {
        commands.setMethodCallHandler(null)
        events.setStreamHandler(null)
        unregisterEventReceiver()
        persistenceCommands.close {}
    }

    private fun requestMicrophonePermission(result: MethodChannel.Result) {
        if (hasMicrophonePermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission-request-in-progress", "A microphone permission request is already active.", null)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MICROPHONE_PERMISSION_REQUEST_CODE,
        )
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", activity.packageName, null)
            }
            activity.startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("app-settings-unavailable", error.message, null)
        }
    }

    private fun startRecording(call: MethodCall, result: MethodChannel.Result) {
        val value = (call.arguments as? Map<*, *>)?.get("format")
        val format = try {
            RecordingFormat.fromWireValue(value).also { it.requireRecordingEncoder(BuildConfig.REC07_MP3_ENABLED) }
        } catch (error: IllegalArgumentException) {
            result.error("recording-format-invalid", "录音格式无效。", null)
            return
        } catch (error: UnsupportedOperationException) {
            result.error("recording-format-unavailable", error.message, null)
            return
        }
        sendRecordingCommand(RecordingService.ACTION_START, result, format)
    }

    private fun sendRecordingCommand(action: String, result: MethodChannel.Result, format: RecordingFormat? = null) {
        if (action == RecordingService.ACTION_START && !hasMicrophonePermission()) {
            result.error("microphone-permission-required", "Microphone permission is required to record.", null)
            return
        }

        try {
            val commandIntent = RecordingService.commandIntent(activity, action, format)
            if (action == RecordingService.ACTION_START && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(commandIntent)
            } else {
                activity.startService(commandIntent)
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("recording-command-failed", error.message, null)
        }
    }

    private fun hasMicrophonePermission(): Boolean {
        return ActivityCompat.checkSelfPermission(
            activity,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun registerEventReceiver() {
        if (receiverRegistered) {
            return
        }
        val filter = IntentFilter().apply {
            addAction(RecordingService.EVENT_STATE)
            addAction(RecordingService.EVENT_FILE_READY)
            addAction(RecordingService.EVENT_ERROR)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(eventReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(eventReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun unregisterEventReceiver() {
        if (!receiverRegistered) {
            return
        }
        activity.unregisterReceiver(eventReceiver)
        receiverRegistered = false
    }

    private fun Map<String, Any?>.withEventType(): Map<String, Any?> {
        return mapOf("type" to "state") + this
    }

    companion object {
        private const val COMMAND_CHANNEL_NAME = "io.github.renial.ya_recorder/recording_commands"
        private const val EVENT_CHANNEL_NAME = "io.github.renial.ya_recorder/recording_events"
        private const val MICROPHONE_PERMISSION_REQUEST_CODE = 901
    }
}
