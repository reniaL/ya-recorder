package io.github.renial.ya_recorder

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import java.io.File

/** Full decode in codec-sized buffers. Used for normal commits and recovery;
 * metadata or an extension alone cannot make a file eligible for the index.
 */
internal object AndroidRecordingMedia {
    fun validate(file: File, recordingFormat: RecordingFormat): Long {
        check(file.isFile && file.length() > 0)
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(file.absolutePath)
            check(extractor.trackCount == 1) { "Unexpected recording tracks" }
            val format = extractor.getTrackFormat(0)
            val mime = checkNotNull(format.getString(MediaFormat.KEY_MIME))
            check(mime == if (recordingFormat == RecordingFormat.MP3) "audio/mpeg" else "audio/mp4a-latm")
            val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            check(rate == 44100 && channels in 1..2)
            if (recordingFormat == RecordingFormat.MP3) check(channels == 1)
            extractor.selectTrack(0)
            val codec = MediaCodec.createDecoderByType(mime)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false
            var frames = 0L
            var outputChannels = channels
            var bytesPerSample = 2
            val started = SystemClock.elapsedRealtime()
            var lastProgress = started
            while (!outputEnded) {
                val now = SystemClock.elapsedRealtime()
                check(now - lastProgress < 10000 && now - started < 120000) { "Media validation timed out" }
                if (!inputEnded) {
                    val index = codec.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val buffer = checkNotNull(codec.getInputBuffer(index))
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                        lastProgress = SystemClock.elapsedRealtime()
                    }
                }
                val index = codec.dequeueOutputBuffer(info, 10000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val output = codec.outputFormat
                    check(output.getInteger(MediaFormat.KEY_SAMPLE_RATE) == rate)
                    outputChannels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    check(outputChannels == channels)
                    val encoding = if (output.containsKey(MediaFormat.KEY_PCM_ENCODING))
                        output.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                    bytesPerSample = when (encoding) {
                        AudioFormat.ENCODING_PCM_16BIT -> 2
                        AudioFormat.ENCODING_PCM_FLOAT -> 4
                        else -> error("Unsupported decoded PCM format")
                    }
                    lastProgress = SystemClock.elapsedRealtime()
                } else if (index >= 0) {
                    check(info.size % (bytesPerSample * outputChannels) == 0)
                    frames += info.size / (bytesPerSample * outputChannels)
                    outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(index, false)
                    lastProgress = SystemClock.elapsedRealtime()
                }
            }
            val duration = frames * 1000 / rate
            check(duration > 0) { "No decodable recording audio" }
            if (format.containsKey(MediaFormat.KEY_DURATION)) {
                val mediaDuration = format.getLong(MediaFormat.KEY_DURATION) / 1000
                check(mediaDuration > 0 && kotlin.math.abs(duration - mediaDuration) <= 150) {
                    "Decoded duration disagrees with media duration"
                }
            }
            return duration
        } finally {
            try { decoder?.release() } finally { extractor.release() }
        }
    }
}
