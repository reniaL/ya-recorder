package io.github.renial.ya_recorder.mp3prototype

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import org.json.JSONObject
import java.io.File
import java.nio.ByteOrder

internal object MediaValidation {
    // Decode the entire output, in bounded buffers, rather than trusting a suffix.
    fun decode(file: File): JSONObject {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(file.absolutePath)
            check(extractor.trackCount > 0) { "No audio track" }
            val format = extractor.getTrackFormat(0)
            check(format.getString(MediaFormat.KEY_MIME) == "audio/mpeg") { "Output is not MP3" }
            check(format.getInteger(MediaFormat.KEY_SAMPLE_RATE) == PrototypeConfig.SAMPLE_RATE)
            check(format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == 1)
            extractor.selectTrack(0)
            val codec = MediaCodec.createDecoderByType("audio/mpeg")
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false
            var samples = 0L
            var peak = 0
            var lastProgress = SystemClock.elapsedRealtime()
            while (!outputEnded) {
                check(SystemClock.elapsedRealtime() - lastProgress < 10000) { "Decoder made no progress" }
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
                    if (output.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        check(output.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_16BIT)
                    }
                } else if (index >= 0) {
                    if (info.size > 0) {
                        val buffer = checkNotNull(codec.getOutputBuffer(index)).duplicate().order(ByteOrder.LITTLE_ENDIAN)
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        while (buffer.remaining() >= 2) {
                            peak = maxOf(peak, kotlin.math.abs(buffer.short.toInt()))
                            samples++
                        }
                    }
                    outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(index, false)
                    lastProgress = SystemClock.elapsedRealtime()
                }
            }
            check(samples > 0) { "No decoded samples" }
            return JSONObject().put("mime", "audio/mpeg")
                .put("mediaDurationMs", format.getLong(MediaFormat.KEY_DURATION) / 1000)
                .put("decodedSamples", samples).put("decodedPeak", peak)
        } finally {
            decoder?.release()
            extractor.release()
        }
    }
}
