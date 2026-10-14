package io.github.renial.ya_recorder

import java.io.File

/** The probe exercises the same container checks and decoder used for saving. */
internal object AacAdtsProbeMedia {
    fun inspect(file: File): Map<String, Any> {
        val audio = AndroidRecordingMedia.inspect(file, RecordingFormat.AAC)
        return mapOf("container" to "adts", "codec" to "aac", "profile" to "LC",
            "sampleRate" to audio.sampleRate, "channels" to audio.channels,
            "decodedFrames" to audio.frames, "decodedDurationMs" to audio.durationMs,
            "fullDecode" to true)
    }
}
