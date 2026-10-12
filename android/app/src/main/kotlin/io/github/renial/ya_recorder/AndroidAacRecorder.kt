package io.github.renial.ya_recorder

import android.media.MediaRecorder
import java.io.File

/** AAC-LC with the container fixed for this recorder's session. */
internal class AndroidAacRecorder(private val format: RecordingFormat) : AacRecorder {
    private val recorder = MediaRecorder()

    override fun prepare(temporaryFile: File) {
        recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        recorder.setOutputFormat(outputFormat(format))
        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        recorder.setAudioEncodingBitRate(128000)
        recorder.setAudioSamplingRate(44100)
        recorder.setOutputFile(temporaryFile.absolutePath)
        recorder.prepare()
    }

    override fun start() = recorder.start()
    override fun pause() = recorder.pause()
    override fun resume() = recorder.resume()
    override fun stop() = recorder.stop()
    override fun reset() = recorder.reset()
    override fun release() = recorder.release()

    companion object {
        fun outputFormat(format: RecordingFormat): Int = when (format) {
            RecordingFormat.AAC -> MediaRecorder.OutputFormat.AAC_ADTS
            RecordingFormat.M4A -> MediaRecorder.OutputFormat.MPEG_4
            RecordingFormat.MP3 -> throw IllegalArgumentException("MP3 requires its own recording backend")
        }
    }
}
