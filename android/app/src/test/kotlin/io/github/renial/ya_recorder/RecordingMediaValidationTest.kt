package io.github.renial.ya_recorder

import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RecordingMediaValidationTest {
    @get:Rule val temporary = TemporaryFolder()
    private fun sample(bytes: ByteArray): File = File(temporary.root, "sample.aac").apply { writeBytes(bytes) }

    @Test fun completeAdtsFramesAcceptVariableSizesAndCrcHeaders() {
        val bytes = adtsFrame(4) + adtsFrame(3000) + adtsFrame(12, crc = true)
        val file = sample(bytes)
        RecordingMediaValidation.validateContainer(file, RecordingFormat.AAC)
        assertArrayEquals(bytes, file.readBytes())
    }

    @Test fun truncatedHeaderPayloadAndTrailingGarbageAreRejectedWithoutChangingTheFile() {
        val frame = adtsFrame(10)
        for (bytes in listOf(byteArrayOf(), frame.copyOf(5), frame.dropLast(1).toByteArray(),
            frame + frame.copyOf(4), frame + ByteArray(8))) {
            val file = sample(bytes)
            assertThrows(Exception::class.java) { RecordingMediaValidation.validateContainer(file, RecordingFormat.AAC) }
            assertArrayEquals(bytes, file.readBytes())
        }
    }

    @Test fun wrongSyncLayerProfileRateAndEmptyFrameAreRejected() {
        val frame = adtsFrame(10)
        val invalid = listOf(
            frame.copyOf().apply { this[0] = 0 },
            frame.copyOf().apply { this[1] = 0xf3.toByte() },
            frame.copyOf().apply { this[2] = 0x10 }, // AAC Main, not LC.
            frame.copyOf().apply { this[2] = 0x4c }, // 48 kHz, not 44.1 kHz.
            adtsFrame(0),
        )
        for (bytes in invalid) {
            assertThrows(IllegalStateException::class.java) {
                RecordingMediaValidation.validateContainer(sample(bytes), RecordingFormat.AAC)
            }
        }
    }

    @Test fun formatIsTakenFromTheContainerRatherThanTheExtension() {
        val mp4Header = byteArrayOf(0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70) + ByteArray(16)
        val file = sample(mp4Header)
        RecordingMediaValidation.validateContainer(file, RecordingFormat.M4A)
        assertThrows(IllegalStateException::class.java) { RecordingMediaValidation.validateContainer(file, RecordingFormat.AAC) }
        file.writeBytes(adtsFrame(10))
        assertThrows(IllegalStateException::class.java) { RecordingMediaValidation.validateContainer(file, RecordingFormat.M4A) }
    }

    @Test fun aacDurationUsesDecodedSamplesEvenWhenMetadataIsAbsentZeroOrEstimated() {
        for (metadata in listOf(null, 0L, 3000L, 100000L)) {
            assertEquals(3000L, RecordingMediaValidation.decodedDurationMs(RecordingFormat.AAC, 132300, 44100, metadata))
        }
        assertEquals(23L, RecordingMediaValidation.decodedDurationMs(RecordingFormat.AAC, 1024, 44100, null))
    }

    @Test fun m4aAndMp3RetainTheirExistingMetadataDurationChecks() {
        for (format in listOf(RecordingFormat.M4A, RecordingFormat.MP3)) {
            assertEquals(3000L, RecordingMediaValidation.decodedDurationMs(format, 132300, 44100, null))
            assertEquals(3000L, RecordingMediaValidation.decodedDurationMs(format, 132300, 44100, 3150))
            for (metadata in listOf(0L, 2000L, 3151L)) {
                assertThrows(IllegalStateException::class.java) {
                    RecordingMediaValidation.decodedDurationMs(format, 132300, 44100, metadata)
                }
            }
        }
    }

    @Test fun emptyDecodedAudioNeverBecomesARecordingUsingMetadataAlone() {
        for (format in RecordingFormat.entries) {
            assertThrows(IllegalStateException::class.java) {
                RecordingMediaValidation.decodedDurationMs(format, 0, 44100, 3000)
            }
        }
    }
}

/** Framing fixture only: this payload is not a real AAC recording. */
internal fun adtsFrame(payloadSize: Int, crc: Boolean = false): ByteArray {
    val size = payloadSize + if (crc) 9 else 7
    val header = byteArrayOf(0xff.toByte(), (if (crc) 0xf0 else 0xf1).toByte(), 0x50,
        (0x40 or (size shr 11)).toByte(), (size shr 3).toByte(),
        (((size and 7) shl 5) or 31).toByte(), 0xfc.toByte())
    return header + (if (crc) ByteArray(2) else byteArrayOf()) + ByteArray(payloadSize)
}
