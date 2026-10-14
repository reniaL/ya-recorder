package io.github.renial.ya_recorder

import java.io.File
import java.io.RandomAccessFile
import kotlin.math.abs

/** Container checks only. Audio payloads still require a full platform decode. */
internal object RecordingMediaValidation {
    fun validateContainer(file: File, format: RecordingFormat) {
        when (format) {
            RecordingFormat.AAC -> validateAdts(file)
            RecordingFormat.M4A -> RandomAccessFile(file, "r").use {
                it.readInt() // First MP4 box size; MediaExtractor validates the boxes.
                check(it.readInt() == 0x66747970) { "Expected an MP4 ftyp box for M4A" }
            }
            RecordingFormat.MP3 -> Unit // Preserve the existing MP3 decode/repair path.
        }
    }

    private fun validateAdts(file: File) = RandomAccessFile(file, "r").use { input ->
        val header = ByteArray(7)
        check(input.length() > 0) { "Empty ADTS recording" }
        while (input.filePointer < input.length()) {
            val start = input.filePointer
            input.readFully(header) // An incomplete last header is a failure, not EOF.
            val second = header[1].toInt() and 255
            check((header[0].toInt() and 255) == 255 && (second and 246) == 240) {
                "Invalid ADTS sync or layer"
            }
            val profile = ((header[2].toInt() and 192) shr 6) + 1
            val rateIndex = (header[2].toInt() and 60) shr 2
            check(profile == 2 && rateIndex == 4) { "Expected AAC-LC at 44100 Hz" }
            val headerSize = if ((second and 1) == 1) 7 else 9
            val frameSize = ((header[3].toInt() and 3) shl 11) or
                ((header[4].toInt() and 255) shl 3) or ((header[5].toInt() and 255) shr 5)
            check(frameSize > headerSize && start + frameSize <= input.length()) {
                "Incomplete ADTS frame"
            }
            input.seek(start + frameSize)
        }
    }

    fun decodedDurationMs(
        format: RecordingFormat,
        frames: Long,
        sampleRate: Int,
        mediaDurationMs: Long?,
    ): Long {
        val duration = frames * 1000 / sampleRate
        check(duration > 0) { "No decodable recording audio" }
        // ADTS duration can be a bitrate estimate; PCM samples are authoritative.
        if (format != RecordingFormat.AAC && mediaDurationMs != null) {
            check(mediaDurationMs > 0 && abs(duration - mediaDurationMs) <= 150) {
                "Decoded duration disagrees with media duration"
            }
        }
        return duration
    }
}
