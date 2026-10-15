package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CancellationException

class BackupStreamCopyTest {
    @Test fun copiesNonSeekableInputInBoundedChunks() {
        var remaining = 1024 * 1024 + 7
        var largestRead = 0
        val input = object : InputStream() {
            override fun read(): Int = error("single-byte IO forbidden")
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                largestRead = maxOf(largestRead, len)
                if (remaining == 0) return -1
                val count = minOf(remaining, len, 12345)
                b.fill(42, off, off + count)
                remaining -= count
                return count
            }
        }
        val out = ByteArrayOutputStream()
        var progress = 0L
        val size = BackupStreamCopy.copy(input, out, { false }, { assertTrue(it > progress); progress = it })
        assertEquals(1024 * 1024 + 7L, size)
        assertEquals(size, progress)
        assertTrue(largestRead <= 64 * 1024)
        assertTrue(out.toByteArray().all { it == 42.toByte() })
    }

    @Test fun cancellationAfterReadPreventsWrite() {
        var cancelled = false
        val input = object : ByteArrayInputStream(ByteArray(16)) {
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                cancelled = true
                return super.read(b, off, len)
            }
        }
        val out = ByteArrayOutputStream()
        assertThrows(CancellationException::class.java) { BackupStreamCopy.copy(input, out, { cancelled }, {}) }
        assertEquals(0, out.size())
    }

    @Test fun cancellationBetweenChunksStopsRemainingIO() {
        val out = ByteArrayOutputStream()
        var cancelled = false
        assertThrows(CancellationException::class.java) {
            BackupStreamCopy.copy(ByteArrayInputStream(ByteArray(200000)), out, { cancelled }, { cancelled = true })
        }
        assertEquals(65536, out.size())
    }

    @Test fun refusesOversizeInputBeforeWritingBeyondLimit() {
        val out = ByteArrayOutputStream()
        assertThrows(IOException::class.java) {
            BackupStreamCopy.copy(ByteArrayInputStream(ByteArray(16)), out, { false }, {}, limit = 15)
        }
        assertEquals(0, out.size())
    }

    @Test fun propagatesProviderReadWriteAndFlushFailures() {
        val input = object : InputStream() { override fun read(): Int = throw IOException("read") }
        assertThrows(IOException::class.java) { BackupStreamCopy.copy(input, ByteArrayOutputStream(), { false }, {}) }
        val writeFail = object : OutputStream() { override fun write(b: Int) { throw IOException("write") } }
        assertThrows(IOException::class.java) { BackupStreamCopy.copy(ByteArrayInputStream(byteArrayOf(1)), writeFail, { false }, {}) }
        val flushFail = object : ByteArrayOutputStream() { override fun flush() { throw IOException("flush") } }
        assertThrows(IOException::class.java) { BackupStreamCopy.copy(ByteArrayInputStream(byteArrayOf()), flushFail, { false }, {}) }
    }

    @Test fun emptySourceIsAValidTransportNotAValidBackup() {
        assertEquals(0L, BackupStreamCopy.copy(ByteArrayInputStream(byteArrayOf()), ByteArrayOutputStream(), { false }, {}))
    }
}
