package io.github.renial.ya_recorder

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Process
import io.github.renial.ya_recorder.mp3.LameEncoder
import java.io.File

internal class AndroidPcmSource : PcmSource {
    private val recorder: AudioRecord

    init {
        val minimum = AudioRecord.getMinBufferSize(44100, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "Unsupported microphone configuration: $minimum" }
        recorder = try {
            AudioRecord(MediaRecorder.AudioSource.MIC, 44100, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum * 2, 4410 * 4))
        } catch (error: SecurityException) {
            // Permission can be revoked after the bridge's preflight check.
            throw IllegalStateException("Microphone permission is unavailable", error)
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            throw IllegalStateException("Microphone initialization failed")
        }
    }

    override fun start() {
        recorder.startRecording()
        check(recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Microphone did not start" }
    }
    override fun onCaptureThread() = Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
    override fun read(buffer: ShortArray): Int = recorder.read(buffer, 0, buffer.size, AudioRecord.READ_NON_BLOCKING)
    override fun stop() = recorder.stop()
    override fun release() = recorder.release()
}

internal class AndroidMp3Encoder : Mp3Encoder {
    private val native = LameEncoder()
    private var handle = 0L
    override fun open(output: File) {
        // Development candidate, not the final device-accepted parameter set.
        handle = native.open(output.absolutePath, 64, 5)
        check(handle != 0L) { "LAME initialization failed" }
    }
    override fun encode(samples: ShortArray) {
        check(native.encode(handle, samples, samples.size) >= 0) { "MP3 encoding or file write failed" }
    }
    override fun finish() {
        check(native.finish(handle) == 0) { "MP3 flush, tag or sync failed" }
    }
    override fun close() {
        if (handle != 0L) native.close(handle)
        handle = 0L
    }
}
