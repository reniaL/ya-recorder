package io.github.renial.ya_recorder

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import java.io.File

/** Probe-only decode: measure PCM frames, without trusting ADTS duration estimates. */
internal object AacAdtsProbeMedia {
    fun inspect(file: File): Map<String, Any> {
        val header = ByteArray(7)
        val headerSize = file.inputStream().use { it.read(header) }
        check(headerSize == 7 && (header[0].toInt() and 255) == 255 && (header[1].toInt() and 246) == 240) {
            "Not an ADTS header"
        }
        val profile = ((header[2].toInt() and 192) shr 6) + 1
        check(profile == 2) { "Expected AAC-LC" }
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(file.absolutePath)
            check(extractor.trackCount == 1)
            val format = extractor.getTrackFormat(0)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            check(mime == "audio/mp4a-latm" && rate == 44100 && channels in 1..2)
            extractor.selectTrack(0)
            val codec = MediaCodec.createDecoderByType(mime)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var frames = 0L
            var bytesPerFrame = 2 * channels
            var inputEnded = false
            var outputEnded = false
            val deadline = SystemClock.elapsedRealtime() + 30000
            while (!outputEnded) {
                check(!Thread.currentThread().isInterrupted && SystemClock.elapsedRealtime() < deadline) {
                    "Decode interrupted or timed out"
                }
                if (!inputEnded) {
                    val index = codec.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val size = extractor.readSampleData(codec.getInputBuffer(index)!!, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = codec.dequeueOutputBuffer(info, 10000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val output = codec.outputFormat
                    check(output.getInteger(MediaFormat.KEY_SAMPLE_RATE) == rate)
                    check(output.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == channels)
                    val encoding = if (output.containsKey(MediaFormat.KEY_PCM_ENCODING))
                        output.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                    bytesPerFrame = channels * when (encoding) {
                        AudioFormat.ENCODING_PCM_16BIT -> 2
                        AudioFormat.ENCODING_PCM_FLOAT -> 4
                        else -> error("Unsupported PCM encoding")
                    }
                } else if (index >= 0) {
                    check(info.size % bytesPerFrame == 0)
                    frames += info.size / bytesPerFrame
                    outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(index, false)
                }
            }
            check(frames > 0)
            return mapOf("container" to "adts", "codec" to "aac", "profile" to "LC",
                "sampleRate" to rate, "channels" to channels, "decodedFrames" to frames,
                "decodedDurationMs" to frames * 1000 / rate, "fullDecode" to true)
        } finally {
            try { decoder?.release() } finally { extractor.release() }
        }
    }
}
