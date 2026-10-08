package io.github.renial.ya_recorder

import java.io.File

/** One backend per session. Commands are serialized by RecordingService.
 *
 * prepare/start are separate so the service can enter the foreground before
 * microphone capture starts. stop finishes the temporary output and releases
 * capture resources before returning; it never moves files or publishes saved.
 * cancel/release are idempotent and never remove files (the service owns them).
 * release abandons capture without attempting to finalize a failed recording.
 */
interface RecordingBackend {
    val format: RecordingFormat
    // MP3 uses accepted PCM samples; M4A continues to use the service clock.
    val elapsedMs: Long? get() = null
    val isQuiescent: Boolean get() = true
    fun setFailureListener(listener: (Throwable) -> Unit) {}
    fun prepare(temporaryFile: File)
    fun start()
    fun pause()
    fun resume()
    fun stop()
    fun cancel()
    fun release()
}

class RecordingBackendFactory(
    private val createM4a: () -> RecordingBackend = { M4aRecordingBackend() },
    private val mp3Enabled: Boolean = false,
    private val createMp3: () -> RecordingBackend = { Mp3RecordingBackend() },
) {
    fun create(format: RecordingFormat): RecordingBackend {
        format.requireRecordingEncoder(mp3Enabled)
        return when (format) {
            RecordingFormat.M4A -> createM4a().also {
                check(it.format == format) { "Recording backend format does not match the session" }
            }
            RecordingFormat.MP3 -> createMp3().also {
                check(it.format == format) { "Recording backend format does not match the session" }
            }
        }
    }
}
