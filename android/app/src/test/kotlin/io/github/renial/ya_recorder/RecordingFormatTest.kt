package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Test

class RecordingFormatTest {
    @Test fun protocolAndPathsMatchBothFormats() {
        assertEquals("audio/mp4", RecordingFormat.fromWireValue("m4a").mimeType)
        assertEquals("audio/mpeg", RecordingFormat.fromWireValue("mp3").mimeType)
        assertEquals("recording-one.m4a", RecordingFormat.M4A.completedFileName("one"))
        assertEquals("recording-one.m4a.part", RecordingFormat.M4A.temporaryFileName("one"))
        assertEquals("recording-one.mp3", RecordingFormat.MP3.completedFileName("one"))
        assertEquals("recording-one.mp3.part", RecordingFormat.MP3.temporaryFileName("one"))
    }

    @Test fun missingOrUnknownFormatDoesNotFallBack() {
        for (value in listOf(null, "", "wav", "M4A", 42)) {
            assertThrows(IllegalArgumentException::class.java) { RecordingFormat.fromWireValue(value) }
        }
    }

    @Test fun unavailableMp3EncoderIsRejectedBeforeStarting() {
        RecordingFormat.M4A.requireRecordingEncoder()
        assertThrows(UnsupportedOperationException::class.java) { RecordingFormat.MP3.requireRecordingEncoder() }
    }

    @Test fun formatCannotIntroduceUnsafeFileNames() {
        for (format in RecordingFormat.entries) {
            for (id in listOf("", "../one", "one/two", "one\\two")) {
                assertThrows(IllegalArgumentException::class.java) { format.temporaryFileName(id) }
            }
        }
    }
}
