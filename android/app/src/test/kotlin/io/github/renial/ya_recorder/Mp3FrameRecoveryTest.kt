package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class Mp3FrameRecoveryTest {
    @get:Rule val temporary = TemporaryFolder()
    private fun frame(): ByteArray = ByteArray(208).apply {
        this[0] = 0xff.toByte(); this[1] = 0xfb.toByte(); this[2] = 0x50; this[3] = 0xc0.toByte()
    }
    private fun repair(bytes: ByteArray): File {
        val source = temporary.newFile("take.mp3.part").apply { writeBytes(bytes) }
        val target = File(temporary.root, "repair.mp3")
        Mp3FrameRecovery.copyCompletePrefix(source, target)
        assertArrayEquals(bytes, source.readBytes())
        return target
    }
    @Test fun partialTailIsExcludedWithoutResynchronizing() {
        val bytes = frame() + frame() + frame().copyOf(103)
        assertEquals(416L, repair(bytes).length())
    }
    @Test fun staleInfoTagIsDisabledOnlyInRepairCopy() {
        val first = frame().apply { "Info".toByteArray().copyInto(this, 21) }
        val result = repair(first + frame()).readBytes()
        assertArrayEquals(ByteArray(4), result.copyOfRange(21, 25))
        assertArrayEquals(first.copyOfRange(0, 21), result.copyOfRange(0, 21))
    }
    @Test fun damagedHeaderStopsPrefixInsteadOfFindingLaterFrames() {
        assertEquals(416L, repair(frame() + frame() + ByteArray(208) + frame()).length())
    }
    @Test fun emptyOrUnsupportedAudioAndSingleFrameAreRejected() {
        for ((index, bytes) in listOf(ByteArray(0), frame(), ByteArray(1000), frame().apply { this[1] = 0xf3.toByte() }).withIndex()) {
            val source = temporary.newFile("bad$index").apply { writeBytes(bytes) }
            try {
                Mp3FrameRecovery.copyCompletePrefix(source, File(temporary.root, "out$index"))
                fail("Unsupported file was repaired")
            } catch (_: IllegalStateException) { }
            assertArrayEquals(bytes, source.readBytes())
        }
    }
}
