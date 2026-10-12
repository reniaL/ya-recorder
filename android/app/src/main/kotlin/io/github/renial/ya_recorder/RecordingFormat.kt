package io.github.renial.ya_recorder

/** Stable values shared with Dart and SQLite; parsing never falls back. */
enum class RecordingFormat(val wireName: String, val extension: String, val mimeType: String) {
    M4A("m4a", "m4a", "audio/mp4"),
    AAC("aac", "aac", "audio/aac"),
    MP3("mp3", "mp3", "audio/mpeg");

    fun completedFileName(id: String): String {
        require(id.matches(Regex("^[A-Za-z0-9_-]+$"))) { "Invalid recording identifier" }
        return "recording-$id.$extension"
    }

    fun temporaryFileName(id: String): String = "${completedFileName(id)}.part"

    fun requireRecordingEncoder(mp3Enabled: Boolean = false) {
        // AAC is a storage/protocol format; its recorder is added in REC-08 step 3.
        if (this == AAC) throw UnsupportedOperationException("当前版本暂不支持 AAC 录音。")
        if (this == MP3 && !mp3Enabled) throw UnsupportedOperationException("当前版本暂不支持 MP3 录音。")
    }

    companion object {
        fun availableForRecording(mp3Enabled: Boolean): List<RecordingFormat> =
            if (mp3Enabled) listOf(M4A, MP3) else listOf(M4A)

        fun fromWireValue(value: Any?): RecordingFormat {
            return entries.firstOrNull { it.wireName == value }
                ?: throw IllegalArgumentException("Unsupported recording format: $value")
        }
    }
}
