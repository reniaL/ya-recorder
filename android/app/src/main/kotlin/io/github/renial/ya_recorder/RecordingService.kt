package io.github.renial.ya_recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.SystemClock
import java.io.File
import java.util.UUID

class RecordingService : Service() {
    private val handler = Handler()

    private var recorder: MediaRecorder? = null
    private var session: ActiveSession? = null
    private var state = State.IDLE

    private val ticker = object : Runnable {
        override fun run() {
            if (state == State.RECORDING) {
                publishState()
                handler.postDelayed(this, STATUS_INTERVAL_MS)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRecording()
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> stopRecording()
            ACTION_CANCEL -> cancelRecording()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        releaseRecorder()
        super.onDestroy()
    }

    private fun startRecording() {
        if (state != State.IDLE && state != State.FAILED) {
            publishState()
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
            temporaryFile = File(recoveryDirectory, "recording-$recordingId.m4a.part"),
            completedFile = File(recordingsDirectory, "recording-$recordingId.m4a"),
        )
        session = activeSession
        state = State.PREPARING
        publishState()

        try {
            activeSession.temporaryFile.delete()
            val newRecorder = MediaRecorder()
            recorder = newRecorder
            newRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            newRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            newRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            newRecorder.setAudioEncodingBitRate(AUDIO_BIT_RATE)
            newRecorder.setAudioSamplingRate(AUDIO_SAMPLE_RATE)
            newRecorder.setOutputFile(activeSession.temporaryFile.absolutePath)
            newRecorder.prepare()
            startForeground(NOTIFICATION_ID, createNotification())
            newRecorder.start()
            activeSession.segmentStartedAtMs = SystemClock.elapsedRealtime()
            state = State.RECORDING
            publishState()
            handler.post(ticker)
        } catch (error: Exception) {
            releaseRecorder()
            fail("recording-start-failed", error.message ?: "Unable to start recording.")
        }
    }

    private fun pauseRecording() {
        if (state != State.RECORDING) {
            publishState()
            return
        }

        try {
            recorder?.pause()
            session?.accumulateElapsedTime()
            state = State.PAUSED
            handler.removeCallbacks(ticker)
            publishState()
        } catch (error: Exception) {
            fail("recording-pause-failed", error.message ?: "Unable to pause recording.")
        }
    }

    private fun resumeRecording() {
        if (state != State.PAUSED) {
            publishState()
            return
        }

        try {
            recorder?.resume()
            session?.segmentStartedAtMs = SystemClock.elapsedRealtime()
            state = State.RECORDING
            publishState()
            handler.post(ticker)
        } catch (error: Exception) {
            fail("recording-resume-failed", error.message ?: "Unable to resume recording.")
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
            recorder?.stop()
            releaseRecorder()
            val durationMs = readDuration(activeSession.completedFile, activeSession.temporaryFile)
            moveToCompletedFile(activeSession)
            publishSaved(activeSession, durationMs)
            resetToIdle()
        } catch (error: Exception) {
            releaseRecorder()
            fail("recording-save-failed", error.message ?: "Unable to save recording.")
        }
    }

    private fun cancelRecording() {
        if (state != State.PREPARING && state != State.RECORDING && state != State.PAUSED) {
            publishState()
            return
        }

        val wasPreparing = state == State.PREPARING
        state = State.DISCARDING
        handler.removeCallbacks(ticker)
        publishState()
        try {
            if (!wasPreparing) {
                recorder?.stop()
            }
        } catch (_: RuntimeException) {
            // A short recording may not have enough samples to be stopped cleanly.
        } finally {
            releaseRecorder()
            session?.temporaryFile?.delete()
            resetToIdle()
        }
    }

    private fun moveToCompletedFile(activeSession: ActiveSession) {
        if (!activeSession.temporaryFile.exists() || activeSession.temporaryFile.length() <= 0) {
            throw IllegalStateException("The temporary recording file is unavailable.")
        }
        if (activeSession.completedFile.exists() && !activeSession.completedFile.delete()) {
            throw IllegalStateException("Unable to replace the completed recording file.")
        }
        if (!activeSession.temporaryFile.renameTo(activeSession.completedFile)) {
            throw IllegalStateException("Unable to finalize the recording file.")
        }
    }

    private fun readDuration(completedFile: File, temporaryFile: File): Long {
        val recordingFile = if (completedFile.exists()) completedFile else temporaryFile
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(recordingFile.absolutePath)
            val duration = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION,
            )?.toLongOrNull()
            return duration ?: throw IllegalStateException("The recording has no readable duration.")
        } finally {
            retriever.release()
        }
    }

    private fun releaseRecorder() {
        recorder?.run {
            try {
                reset()
            } catch (_: RuntimeException) {
                // The recorder may already be in an error state.
            }
            release()
        }
        recorder = null
    }

    private fun fail(code: String, message: String) {
        handler.removeCallbacks(ticker)
        state = State.FAILED
        publishState()
        publishError(code, message)
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
        val activeSession = session
        val status = mapOf(
            "state" to state.wireName,
            "elapsedMs" to (activeSession?.elapsedMs(state) ?: 0L),
            "canResume" to (state == State.PAUSED),
            "sessionId" to activeSession?.id,
        )
        latestStatus = status
        publish(
            EVENT_STATE,
            Intent().apply {
                putExtra(EXTRA_STATE, status["state"] as String)
                putExtra(EXTRA_ELAPSED_MS, status["elapsedMs"] as Long)
                putExtra(EXTRA_CAN_RESUME, status["canResume"] as Boolean)
                putExtra(EXTRA_SESSION_ID, status["sessionId"] as String?)
            },
        )
    }

    private fun publishSaved(activeSession: ActiveSession, durationMs: Long) {
        publish(
            EVENT_SAVED,
            Intent().apply {
                putExtra(EXTRA_ID, activeSession.id)
                putExtra(EXTRA_FILE_PATH, activeSession.completedFile.absolutePath)
                putExtra(EXTRA_CREATED_AT_MS, activeSession.createdAtMs)
                putExtra(EXTRA_DURATION_MS, durationMs)
                putExtra(EXTRA_FILE_SIZE_BYTES, activeSession.completedFile.length())
                putExtra(EXTRA_WAS_INTERRUPTED, false)
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

        const val EVENT_STATE = "io.github.renial.ya_recorder.event.RECORDING_STATE"
        const val EVENT_SAVED = "io.github.renial.ya_recorder.event.RECORDING_SAVED"
        const val EVENT_ERROR = "io.github.renial.ya_recorder.event.RECORDING_ERROR"

        const val EXTRA_STATE = "state"
        const val EXTRA_ELAPSED_MS = "elapsedMs"
        const val EXTRA_CAN_RESUME = "canResume"
        const val EXTRA_SESSION_ID = "sessionId"
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
        private const val AUDIO_BIT_RATE = 128000
        private const val AUDIO_SAMPLE_RATE = 44100

        @Volatile
        private var latestStatus: Map<String, Any?> = idleStatus()

        fun commandIntent(context: Context, action: String): Intent {
            return Intent(context, RecordingService::class.java).setAction(action)
        }

        fun currentStatus(): Map<String, Any?> = latestStatus

        private fun idleStatus(): Map<String, Any?> {
            return mapOf(
                "state" to "idle",
                "elapsedMs" to 0L,
                "canResume" to false,
                "sessionId" to null,
            )
        }
    }
}