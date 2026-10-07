package io.github.renial.ya_recorder

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class Mp3RecordingBackendTest {
    private val directory = Files.createTempDirectory("mp3-backend-").toFile()
    private val output = File(directory, "recording-one.mp3.part")
    private val source = FakeSource()
    private val encoder = FakeEncoder()
    private val backend = createBackend()

    @After fun cleanup() {
        encoder.allowEncode.countDown()
        try { backend.release() } catch (_: Exception) {}
        directory.deleteRecursively()
    }

    @Test fun preparationOwnsEncoderThreadButDoesNotCapture() {
        backend.prepare(output)
        assertEquals(0, source.starts.get())
        assertEquals(0, backend.acceptedSamples.get())
        assertEquals(0L, backend.elapsedMs)
        backend.cancel()
        backend.cancel()
        assertEquals(listOf("open", "close"), encoder.calls)
        assertEquals(1, source.releases.get())
        assertEquals(1, encoder.threads.distinct().size)
        assertFalse(encoder.threads.contains(Thread.currentThread().name))
    }

    @Test fun pauseFlushesPartialChunkAndResumeKeepsOneContinuousStream() {
        backend.prepare(output)
        backend.start()
        source.emit(1, 2, 3)
        eventually { source.readSamples.get() == 3 }
        backend.pause()
        assertEquals(3, backend.acceptedSamples.get())
        assertFalse(source.emit(99))
        assertEquals(0, encoder.finishes.get())
        backend.resume()
        source.emit(4, 5, 6, 7, 8)
        eventually { source.readSamples.get() == 8 }
        backend.stop()
        backend.stop()
        backend.release()
        assertEquals((1..8).map(Int::toShort), encoder.samples)
        assertEquals(8, backend.encodedSamples.get())
        assertEquals(2, source.starts.get())
        assertEquals(2, source.stops.get())
        assertEquals(1, source.releases.get())
        assertEquals(1, encoder.finishes.get())
        assertEquals(listOf("finish", "close"), encoder.calls.takeLast(2))
        assertEquals(1, encoder.threads.distinct().size)
        assertTrue(output.exists())
        assertEquals(listOf(output.name), directory.list()!!.toList())
    }

    @Test fun durationCountsAcceptedSamplesAndExcludesPausedWallTime() {
        val candidate = createBackend(Mp3Config())
        try {
            candidate.prepare(output)
            candidate.start()
            source.emit(*IntArray(4410) { 1 })
            eventually { candidate.acceptedSamples.get() == 4410L }
            candidate.pause()
            assertEquals(100L, candidate.elapsedMs)
            assertFalse(source.emit(2, 3))
            assertEquals(100L, candidate.elapsedMs)
            candidate.resume()
            source.emit(*IntArray(2205) { 2 })
            eventually { source.readSamples.get() == 6615 }
            candidate.pause()
            assertEquals(150L, candidate.elapsedMs)
            candidate.stop()
            assertEquals(6615L, candidate.encodedSamples.get())
        } finally { candidate.release() }
    }

    @Test fun stopWaitsForAcceptedQueueBeforeFinishingExactlyOnce() {
        encoder.blockEncoding = true
        backend.prepare(output)
        backend.start()
        source.emit(*(1..12).toList().toIntArray())
        await(encoder.encoding)
        eventually { backend.acceptedSamples.get() == 12L }
        val worker = Executors.newSingleThreadExecutor()
        try {
            val stop = worker.submit { backend.stop() }
            eventually { source.releases.get() == 1 }
            assertFalse(stop.isDone)
            assertEquals(0, encoder.finishes.get())
            encoder.allowEncode.countDown()
            stop.get(2, TimeUnit.SECONDS)
            assertEquals((1..12).map(Int::toShort), encoder.samples)
            assertEquals(1, encoder.finishes.get())
            assertEquals(12L, backend.encodedSamples.get())
        } finally { encoder.allowEncode.countDown(); worker.shutdownNow() }
    }

    @Test fun cancelWaitsForInFlightWriteButNeverFlushesOrMovesOutput() {
        encoder.blockEncoding = true
        backend.prepare(output)
        backend.start()
        source.emit(1, 2, 3, 4)
        await(encoder.encoding)
        val worker = Executors.newSingleThreadExecutor()
        try {
            val cancel = worker.submit { backend.cancel() }
            eventually { source.releases.get() == 1 }
            assertFalse(cancel.isDone)
            encoder.allowEncode.countDown()
            cancel.get(2, TimeUnit.SECONDS)
            backend.release()
            assertEquals(0, encoder.finishes.get())
            assertEquals(1, encoder.calls.count { it == "close" })
            assertEquals(listOf(output.name), directory.list()!!.toList())
        } finally { encoder.allowEncode.countDown(); worker.shutdownNow() }
    }

    @Test fun queueOverflowFailsExplicitlyWithoutFlushOrSilentDroppedAudio() {
        encoder.blockEncoding = true
        val bounded = createBackend(Mp3Config(chunkSamples = 4, queueBlocks = 2))
        val failed = CountDownLatch(1)
        val errors = CopyOnWriteArrayList<Throwable>()
        bounded.setFailureListener { errors += it; failed.countDown() }
        try {
            bounded.prepare(output)
            bounded.start()
            source.emit(1, 2, 3, 4)
            await(encoder.encoding)
            source.emit(*IntArray(24) { 5 })
            await(failed)
            eventually { source.releases.get() == 1 }
            assertTrue(errors.single().message!!.contains("overflow"))
            assertEquals(2, bounded.queueHighWater.get())
            assertEquals(12L, bounded.acceptedSamples.get())
            encoder.allowEncode.countDown()
            assertThrows(IllegalStateException::class.java) { bounded.stop() }
            assertEquals(0, encoder.finishes.get())
            assertTrue(output.exists())
        } finally { encoder.allowEncode.countDown(); bounded.release() }
    }

    @Test fun nativeLoadFailureCleansMicrophoneAndReportsUnavailableWithoutFallback() {
        val failed = CountDownLatch(1)
        val candidate = Mp3RecordingBackend({ source }, { throw UnsatisfiedLinkError("missing ABI") })
        candidate.setFailureListener { failed.countDown() }
        try {
            val error = assertThrows(IllegalStateException::class.java) { candidate.prepare(output) }
            assertTrue(error.message!!.contains("unavailable"))
            await(failed)
            assertEquals(0, source.starts.get())
            assertEquals(1, source.releases.get())
        } finally { candidate.release() }
    }

    @Test fun encoderOpenFailureClosesPartialEncoderAndReleasesSource() {
        encoder.failAt = "open"
        assertThrows(IllegalStateException::class.java) { backend.prepare(output) }
        assertEquals(listOf("open", "close"), encoder.calls)
        assertEquals(1, source.releases.get())
        assertEquals(0, encoder.finishes.get())
        assertTrue(output.exists())
    }

    @Test fun microphoneStartFailureReleasesBothResources() {
        backend.prepare(output)
        source.failStart = true
        assertThrows(IllegalStateException::class.java) { backend.start() }
        assertEquals(1, source.releases.get())
        assertEquals(listOf("open", "close"), encoder.calls)
    }

    @Test fun permissionFailureBeforeCaptureDoesNotOpenAnEncoderOrFallback() {
        var encoderCreations = 0
        val candidate = Mp3RecordingBackend(
            { throw SecurityException("permission revoked") },
            { encoderCreations++; encoder },
        )
        try {
            assertThrows(SecurityException::class.java) { candidate.prepare(output) }
            assertEquals(0, encoderCreations)
            assertFalse(output.exists())
            assertEquals(0, source.starts.get())
        } finally { candidate.release() }
    }

    @Test fun negativeReadReportsFailureOnceAndStopsCapture() {
        val errors = CopyOnWriteArrayList<Throwable>()
        val failed = CountDownLatch(1)
        backend.setFailureListener { errors += it; failed.countDown() }
        backend.prepare(output)
        source.failRead = true
        backend.start()
        await(failed)
        eventually { source.releases.get() == 1 }
        assertEquals(1, errors.size)
        assertTrue(errors.single().message!!.contains("read failed"))
        assertThrows(IllegalStateException::class.java) { backend.stop() }
        assertEquals(0, encoder.finishes.get())
        assertTrue(output.exists())
    }

    @Test fun encoderWriteFailurePropagatesFromBackgroundWithoutFinishing() {
        val failed = CountDownLatch(1)
        backend.setFailureListener { failed.countDown() }
        encoder.failAt = "encode"
        backend.prepare(output)
        backend.start()
        source.emit(1, 2, 3, 4)
        await(failed)
        eventually { source.releases.get() == 1 }
        assertThrows(IllegalStateException::class.java) { backend.stop() }
        assertEquals(0, encoder.finishes.get())
        assertEquals(1, encoder.calls.count { it == "close" })
        assertTrue(output.exists())
    }

    @Test fun finishFailureRetainsPartAndCannotBeReportedAsLaterSuccess() {
        encoder.failAt = "finish"
        backend.prepare(output)
        backend.start()
        source.emit(1, 2, 3, 4)
        eventually { backend.acceptedSamples.get() == 4L }
        assertThrows(IllegalStateException::class.java) { backend.stop() }
        assertThrows(IllegalStateException::class.java) { backend.stop() }
        assertEquals(1, encoder.finishes.get())
        assertEquals(1, encoder.calls.count { it == "close" })
        assertTrue(output.exists())
    }

    @Test fun emptyTakeFailsSaveAndCanStillBeCancelled() {
        backend.prepare(output)
        backend.start()
        assertThrows(IllegalStateException::class.java) { backend.stop() }
        backend.cancel()
        assertEquals(0, encoder.finishes.get())
        assertEquals(1, source.releases.get())
    }

    @Test fun blockedEncoderTimesOutWithoutDeletingOrPretendingToSave() {
        encoder.blockEncoding = true
        val timed = createBackend(Mp3Config(chunkSamples = 4, joinTimeoutMs = 100))
        try {
            timed.prepare(output)
            timed.start()
            source.emit(1, 2, 3, 4)
            await(encoder.encoding)
            val error = assertThrows(IllegalStateException::class.java) { timed.cancel() }
            assertTrue(error.message!!.contains("did not stop"))
            assertTrue(output.exists())
            encoder.allowEncode.countDown()
            timed.release()
            assertThrows(IllegalStateException::class.java) { timed.stop() }
            assertEquals(0, encoder.finishes.get())
        } finally { encoder.allowEncode.countDown(); timed.release() }
    }

    @Test fun sourceAndEncoderCleanupErrorsKeepTemporaryOutputAndReportCancelFailure() {
        for (encoderFails in listOf(false, true)) {
            val localSource = FakeSource().apply { failRelease = !encoderFails }
            val localEncoder = FakeEncoder().apply { if (encoderFails) failAt = "close" }
            val candidate = Mp3RecordingBackend({ localSource }, { localEncoder })
            try {
                candidate.prepare(output)
                assertThrows(IllegalStateException::class.java) { candidate.cancel() }
                assertEquals(1, localSource.releases.get())
                assertEquals(1, localEncoder.calls.count { it == "close" })
                assertTrue(output.exists())
            } finally { try { candidate.release() } catch (_: Exception) {} }
        }
    }

    @Test fun optedInFactoryRoutesMp3WithoutCreatingAnM4aRecorder() {
        var m4aCreations = 0
        val factory = RecordingBackendFactory(
            createM4a = { m4aCreations++; M4aRecordingBackend() },
            mp3Enabled = true,
            createMp3 = { backend },
        )
        assertSame(backend, factory.create(RecordingFormat.MP3))
        assertEquals(0, m4aCreations)
        RecordingFormat.MP3.requireRecordingEncoder(true)
        assertThrows(IllegalStateException::class.java) { backend.start() }
        assertThrows(IllegalArgumentException::class.java) { backend.prepare(File("one.m4a.part")) }
    }

    private fun createBackend(config: Mp3Config = Mp3Config(chunkSamples = 4)): Mp3RecordingBackend =
        Mp3RecordingBackend({ source }, { encoder }, config)

    private fun await(latch: CountDownLatch) { assertTrue("Worker did not reach the boundary", latch.await(2, TimeUnit.SECONDS)) }
    private fun eventually(condition: () -> Boolean) {
        val end = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
        while (!condition() && System.nanoTime() < end) Thread.sleep(2)
        assertTrue("Worker condition was not reached", condition())
    }

    private class FakeSource : PcmSource {
        val starts = AtomicInteger()
        val stops = AtomicInteger()
        val releases = AtomicInteger()
        val readSamples = AtomicInteger()
        private val input = LinkedBlockingQueue<Short>()
        @Volatile private var running = false
        var failStart = false
        var failRead = false
        var failRelease = false
        fun emit(vararg samples: Int): Boolean {
            if (!running) return false
            samples.forEach { input.offer(it.toShort()) }
            return true
        }
        override fun start() { starts.incrementAndGet(); check(!failStart) { "start failed" }; running = true }
        override fun read(buffer: ShortArray): Int {
            if (failRead) return -6
            var size = 0
            while (size < buffer.size) { buffer[size] = input.poll() ?: break; size++ }
            readSamples.addAndGet(size)
            return size
        }
        override fun stop() { stops.incrementAndGet(); running = false; input.clear() }
        override fun release() { releases.incrementAndGet(); check(!failRelease) { "source release failed" } }
    }

    private class FakeEncoder : Mp3Encoder {
        val samples = CopyOnWriteArrayList<Short>()
        val calls = CopyOnWriteArrayList<String>()
        val threads = CopyOnWriteArrayList<String>()
        val finishes = AtomicInteger()
        val encoding = CountDownLatch(1)
        val allowEncode = CountDownLatch(1)
        var blockEncoding = false
        var failAt: String? = null
        private fun call(name: String) {
            calls += name
            threads += Thread.currentThread().name
            check(failAt != name) { "$name failed" }
        }
        override fun open(output: File) { output.writeBytes(byteArrayOf(1, 2, 3)); call("open") }
        override fun encode(samples: ShortArray) {
            encoding.countDown()
            if (blockEncoding) check(allowEncode.await(5, TimeUnit.SECONDS)) { "test encoder blocked" }
            call("encode")
            this.samples.addAll(samples.toList())
        }
        override fun finish() { finishes.incrementAndGet(); call("finish") }
        override fun close() = call("close")
    }
}
