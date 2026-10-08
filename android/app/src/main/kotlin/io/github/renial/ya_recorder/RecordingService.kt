package io.github.renial.ya_recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.util.UUID

class RecordingService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val commands = SerialRecordingCommands()

    private val backendFactory = RecordingBackendFactory(mp3Enabled = BuildConfig.REC07_MP3_ENABLED)
    private var backend: RecordingBackend? = null
    private var writerQuiescent = true
    private var session: ActiveSession? = null
    private var state = State.IDLE
    private val persistence by lazy { AndroidRecordingPersistence.get(this) }

    private val ticker = object : Runnable {
        override fun run() {
            commands.submit {
                if (state == State.RECORDING) {
                    publishState()
                    handler.removeCallbacks(this)
                    handler.postDelayed(this, STATUS_INTERVAL_MS)
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        commands.submit {
            when (intent?.action) {
                ACTION_START -> startRecording(intent.getStringExtra(EXTRA_FORMAT))
                ACTION_PAUSE -> pauseRecording()
                ACTION_RESUME -> resumeRecording()
                ACTION_STOP -> stopRecording()
                ACTION_CANCEL -> cancelRecording()
                ACTION_INDEX_FINISHED -> {
                    if (session?.id == intent.getStringExtra(EXTRA_ID) && state == State.STOPPING) resetToIdle()
                    else if (session == null) stopSelf()
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        commands.close {
            handler.removeCallbacksAndMessages(null)
            if (releaseBackend()) session?.let { persistence.releaseLease(it.id) }
            latestStatus = idleStatus()
        }
        super.onDestroy()
    }

    private fun startRecording(formatValue: String?) {
        if (state != State.IDLE && state != State.FAILED) {
            publishState()
            return
        }

        val format = try {
            RecordingFormat.fromWireValue(formatValue).also { it.requireRecordingEncoder(BuildConfig.REC07_MP3_ENABLED) }
        } catch (error: IllegalArgumentException) {
            fail("recording-format-invalid", "录音格式无效。")
            return
        } catch (error: UnsupportedOperationException) {
            fail("recording-format-unavailable", error.message ?: "录音编码器不可用。")
            return
        }

        val recordingId = UUID.randomUUID().toString()
        val rootDirectory = File(filesDir, APP_DIRECTORY_NAME)
        val recordingsDirectory = File(rootDirectory, RECORDINGS_DIRECTORY_NAME)
        val recoveryDirectory = File(rootDirectory, RECOVERY_DIRECTORY_NAME)
        if (!recordingsDirectory.mkdirs() && !recordingsDirectory.isDirectory) {
            fail("storage-unavailable", "Unable to create the recordings directory.")
            return
        }
        if (!recoveryDirectory.mkdirs() && !recoveryDirectory.isDirectory) {
            fail("storage-unavailable", "Unable to create the recovery directory.")
            return
        }

        val activeSession = ActiveSession(
            id = recordingId,
            createdAtMs = System.currentTimeMillis(),
            format = format,
            temporaryFile = File(recoveryDirectory, format.temporaryFileName(recordingId)),
            completedFile = File(recordingsDirectory, format.completedFileName(recordingId)),
        )
        session = activeSession
        writerQuiescent = true
        state = State.PREPARING
        publishState()

        try {
            // Enter foreground promptly, before native initialization can wait.
            startForeground(NOTIFICATION_ID, createNotification())
            persistence.begin(activeSession.id, activeSession.createdAtMs, activeSession.format)
            val newBackend = backendFactory.create(activeSession.format)
            backend = newBackend
            writerQuiescent = false
            newBackend.setFailureListener { error ->
                commands.submit {
                    if (backend === newBackend && session === activeSession) {
                        fail("recording-runtime-failed", "MP3 录音已中断，正在检查已录内容。", error)
                    }
                }
            }
            newBackend.prepare(activeSession.temporaryFile)
            check(!commands.isClosed) { "Recording service was destroyed during preparation." }
            newBackend.start()
            activeSession.segmentStartedAtMs = SystemClock.elapsedRealtime()
            state = State.RECORDING
            publishState()
            handler.post(ticker)
        } catch (error: Exception) {
            fail("recording-start-failed", if (format == RecordingFormat.MP3) "无法开始 MP3 录音。"
                else error.message ?: "Unable to start recording.", error)
        }
    }

    private fun pauseRecording() {
        if (state != State.RECORDING) {
            publishState()
            return
        }

        try {
            requireBackend().pause()
            session?.accumulateElapsedTime()
            state = State.PAUSED
            handler.removeCallbacks(ticker)
            publishState()
        } catch (error: Exception) {
            fail("recording-pause-failed", if (session?.format == RecordingFormat.MP3) "无法暂停 MP3 录音，录音已中断。"
                else error.message ?: "Unable to pause recording.", error)
        }
    }

    private fun resumeRecording() {
        if (state != State.PAUSED) {
            publishState()
            return
        }

        try {
            requireBackend().resume()
            session?.segmentStartedAtMs = SystemClock.elapsedRealtime()
            state = State.RECORDING
            publishState()
            handler.post(ticker)
        } catch (error: Exception) {
            fail("recording-resume-failed", if (session?.format == RecordingFormat.MP3) "无法继续 MP3 录音，录音已中断。"
                else error.message ?: "Unable to resume recording.", error)
        }
    }

    private fun stopRecording() {
        if (state != State.RECORDING && state != State.PAUSED) {
            publishState()
            return
        }

        if (state == State.RECORDING) {
            session?.accumulateElapsedTime()
        }
        state = State.STOPPING
        handler.removeCallbacks(ticker)
        publishState()

        val activeSession = session ?: run {
            fail("recording-session-missing", "The active recording session was lost.")
            return
        }

        try {
            requireBackend().stop()
            val acceptedDurationMs = requireBackend().elapsedMs
            check(releaseBackend()) { "Recording cleanup failed" }
            check(!commands.isClosed) { "Recording service was destroyed before file commit." }
            val ready = persistence.finish(activeSession.id, acceptedDurationMs)
            persistence.releaseLease(activeSession.id)
            publishReady(ready)
            // Remain STOPPING/foreground until Flutter's index attempt completes.
        } catch (error: Exception) {
            fail("recording-save-failed", if (activeSession.format == RecordingFormat.MP3) "无法保存 MP3 录音。"
                else error.message ?: "Unable to save recording.", error)
        }
    }

    private fun cancelRecording() {
        if (state != State.PREPARING && state != State.RECORDING && state != State.PAUSED) {
            publishState()
            return
        }

        try {
            persistence.markDiscarding(checkNotNull(session).id)
        } catch (error: Exception) {
            Log.e("RecordingService", "Discard intent could not be persisted", error)
            publishError("recording-cancel-failed", "无法确认放弃录音，请重试。")
            return
        }
        state = State.DISCARDING
        handler.removeCallbacks(ticker)
        publishState()
        try {
            backend?.cancel()
            check(releaseBackend()) { "Recording cleanup failed" }
            persistence.releaseLease(checkNotNull(session).id)
            persistence.discard(checkNotNull(session).id)
        } catch (error: Exception) {
            fail("recording-cancel-failed", if (session?.format == RecordingFormat.MP3) "无法完成 MP3 录音清理。"
                else error.message ?: "Unable to cancel recording.", error)
            return
        }
        resetToIdle()
    }

    private fun requireBackend(): RecordingBackend =
        checkNotNull(backend) { "The active recording backend was lost." }

    private fun releaseBackend(): Boolean {
        val activeBackend = backend
        if (activeBackend == null) return writerQuiescent
        backend = null
        writerQuiescent = try {
            activeBackend.release()
            activeBackend.isQuiescent
        } catch (error: Exception) {
            Log.e("RecordingService", "Recording cleanup failed; lease retained", error)
            false
        }
        return writerQuiescent
    }

    private fun fail(code: String, message: String, cause: Throwable? = null) {
        if (cause != null) Log.e("RecordingService", code, cause)
        handler.removeCallbacks(ticker)
        state = State.FAILED
        publishState()
        val activeSession = session
        val quiescent = releaseBackend()
        if (quiescent && activeSession != null) {
            persistence.releaseLease(activeSession.id)
            try {
                val ready = persistence.recoverOne(activeSession.id)
                if (ready != null && !commands.isClosed) {
                    state = State.STOPPING
                    publishState()
                    publishReady(ready)
                    return
                }
            } catch (recovery: Exception) {
                Log.e("RecordingService", "Recording residual retained", recovery)
            }
        }
        publishError(code, if (code == "recording-runtime-failed") "录音已中断，暂无法保存，残留文件已保留。" else message)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        session = null
        state = State.IDLE
        publishState()
    }

    private fun resetToIdle() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        session = null
        state = State.IDLE
        publishState()
        stopSelf()
    }

    private fun publishState() {
        if (commands.isClosed) return
        val activeSession = session
        val status = mapOf(
            "state" to state.wireName,
            "elapsedMs" to (backend?.elapsedMs ?: activeSession?.elapsedMs(state) ?: 0L),
            "canResume" to (state == State.PAUSED),
            "sessionId" to activeSession?.id,
            "format" to activeSession?.format?.wireName,
        )
        latestStatus = status
        publish(
            EVENT_STATE,
            Intent().apply {
                putExtra(EXTRA_STATE, status["state"] as String)
                putExtra(EXTRA_ELAPSED_MS, status["elapsedMs"] as Long)
                putExtra(EXTRA_CAN_RESUME, status["canResume"] as Boolean)
                putExtra(EXTRA_SESSION_ID, status["sessionId"] as String?)
                putExtra(EXTRA_FORMAT, activeSession?.format?.wireName)
            },
        )
    }

    private fun publishReady(ready: ReadyRecording) {
        val draft = ready.draft
        publish(
            EVENT_FILE_READY,
            Intent().apply {
                putExtra(EXTRA_ID, draft.id)
                putExtra(EXTRA_FILE_PATH, ready.file.absolutePath)
                putExtra(EXTRA_CREATED_AT_MS, draft.createdAtMs)
                putExtra(EXTRA_DURATION_MS, draft.durationMs)
                putExtra(EXTRA_FILE_SIZE_BYTES, draft.fileSizeBytes)
                putExtra(EXTRA_WAS_INTERRUPTED, draft.wasInterrupted)
                putExtra(EXTRA_FORMAT, draft.format.wireName)
            },
        )
    }

    private fun publishError(code: String, message: String) {
        publish(
            EVENT_ERROR,
            Intent().apply {
                putExtra(EXTRA_ERROR_CODE, code)
                putExtra(EXTRA_ERROR_MESSAGE, message)
            },
        )
    }

    private fun publish(event: String, extras: Intent) {
        if (commands.isClosed) return
        sendBroadcast(
            extras.setAction(event).setPackage(packageName),
        )
    }

    private fun createNotification(): Notification {
        val notificationManager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    getString(R.string.recording_notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return notificationBuilder
            .setContentTitle(getString(R.string.recording_notification_title))
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
    }

    private data class ActiveSession(
        val id: String,
        val createdAtMs: Long,
        val format: RecordingFormat,
        val temporaryFile: File,
        val completedFile: File,
        var accumulatedMs: Long = 0L,
        var segmentStartedAtMs: Long? = null,
    ) {
        fun accumulateElapsedTime() {
            val startedAt = segmentStartedAtMs ?: return
            accumulatedMs += SystemClock.elapsedRealtime() - startedAt
            segmentStartedAtMs = null
        }

        fun elapsedMs(state: State): Long {
            val startedAt = segmentStartedAtMs
            return if (state == State.RECORDING && startedAt != null) {
                accumulatedMs + SystemClock.elapsedRealtime() - startedAt
            } else {
                accumulatedMs
            }
        }
    }

    private enum class State(val wireName: String) {
        IDLE("idle"),
        PREPARING("preparing"),
        RECORDING("recording"),
        PAUSED("paused"),
        STOPPING("stopping"),
        DISCARDING("discarding"),
        FAILED("failed"),
    }

    companion object {
        const val ACTION_START = "io.github.renial.ya_recorder.action.START_RECORDING"
        const val ACTION_PAUSE = "io.github.renial.ya_recorder.action.PAUSE_RECORDING"
        const val ACTION_RESUME = "io.github.renial.ya_recorder.action.RESUME_RECORDING"
        const val ACTION_STOP = "io.github.renial.ya_recorder.action.STOP_RECORDING"
        const val ACTION_CANCEL = "io.github.renial.ya_recorder.action.CANCEL_RECORDING"
        const val ACTION_INDEX_FINISHED = "io.github.renial.ya_recorder.action.INDEX_FINISHED"

        const val EVENT_STATE = "io.github.renial.ya_recorder.event.RECORDING_STATE"
        const val EVENT_FILE_READY = "io.github.renial.ya_recorder.event.RECORDING_FILE_READY"
        const val EVENT_ERROR = "io.github.renial.ya_recorder.event.RECORDING_ERROR"

        const val EXTRA_STATE = "state"
        const val EXTRA_ELAPSED_MS = "elapsedMs"
        const val EXTRA_CAN_RESUME = "canResume"
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_FORMAT = "format"
        const val EXTRA_ID = "id"
        const val EXTRA_FILE_PATH = "filePath"
        const val EXTRA_CREATED_AT_MS = "createdAtMs"
        const val EXTRA_DURATION_MS = "durationMs"
        const val EXTRA_FILE_SIZE_BYTES = "fileSizeBytes"
        const val EXTRA_WAS_INTERRUPTED = "wasInterrupted"
        const val EXTRA_ERROR_CODE = "code"
        const val EXTRA_ERROR_MESSAGE = "message"

        private const val APP_DIRECTORY_NAME = "ya_recorder"
        private const val RECORDINGS_DIRECTORY_NAME = "recordings"
        private const val RECOVERY_DIRECTORY_NAME = "recovery"
        private const val NOTIFICATION_CHANNEL_ID = "active_recording"
        private const val NOTIFICATION_ID = 1001
        private const val STATUS_INTERVAL_MS = 250L

        @Volatile
        private var latestStatus: Map<String, Any?> = idleStatus()

        fun commandIntent(context: Context, action: String, format: RecordingFormat? = null): Intent {
            if (action == ACTION_START) require(format != null) { "Start requires a recording format" }
            return Intent(context, RecordingService::class.java).setAction(action).apply {
                if (format != null) putExtra(EXTRA_FORMAT, format.wireName)
            }
        }

        fun currentStatus(): Map<String, Any?> = latestStatus

        private fun idleStatus(): Map<String, Any?> {
            return mapOf(
                "state" to "idle",
                "elapsedMs" to 0L,
                "canResume" to false,
                "sessionId" to null,
                "format" to null,
            )
        }
    }
}
