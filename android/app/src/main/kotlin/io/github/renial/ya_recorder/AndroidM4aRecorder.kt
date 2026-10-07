package io.github.renial.ya_recorder

import android.media.MediaRecorder
import java.io.File

/** The existing MediaRecorder/AAC configuration, isolated from session control. */
internal class AndroidM4aRecorder : M4aRecorder {
    private val recorder = MediaRecorder()

    override fun prepare(temporaryFile: File) {
        recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
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
}
