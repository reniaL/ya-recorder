package io.github.renial.ya_recorder

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class M4aRecordingBackendTest {
    @Test fun prepareDoesNotCaptureBeforeForegroundStart() {
        val recorder = FakeRecorder()
        val output = File("recording-one.m4a.part")
        val backend = M4aRecordingBackend { recorder }
        backend.prepare(output)
        assertEquals(output, recorder.output)
        assertEquals(listOf("prepare"), recorder.calls)
        assertEquals(RecordingFormat.M4A, backend.format)
        backend.release()
    }

    @Test fun pauseAndResumeKeepOneRecorderAndOutputUntilStop() {
        val recorder = FakeRecorder()
        var created = 0
        val backend = M4aRecordingBackend { created++; recorder }
        backend.prepare(File("recording-one.m4a.part"))
        backend.start()
        repeat(2) { backend.pause(); backend.resume() }
        backend.stop()
        backend.stop()
        backend.cancel()
        backend.release()
        assertEquals(1, created)
        assertEquals(
            listOf("prepare", "start", "pause", "resume", "pause", "resume", "stop", "reset", "release"),
            recorder.calls,
        )
    }

    @Test fun pausedRecordingCanBeStoppedWithoutResuming() {
        val recorder = FakeRecorder()
        val backend = prepared(recorder)
        backend.start()
        backend.pause()
        backend.stop()
        assertEquals(listOf("prepare", "start", "pause", "stop", "reset", "release"), recorder.calls)
    }

    @Test fun cancelBeforeStartReleasesWithoutCallingStop() {
        val recorder = FakeRecorder()
        val backend = prepared(recorder)
        backend.cancel()
        backend.cancel()
        backend.release()
        assertEquals(listOf("prepare", "reset", "release"), recorder.calls)
    }

    @Test fun cancelRecordingOrPausedTakeStopsAndReleasesOnce() {
        for (paused in listOf(false, true)) {
            val recorder = FakeRecorder()
            val backend = prepared(recorder)
            backend.start()
            if (paused) backend.pause()
            backend.cancel()
            backend.cancel()
            backend.release()
            assertEquals(1, recorder.calls.count { it == "stop" })
            assertEquals(listOf("stop", "reset", "release"), recorder.calls.takeLast(3))
        }
    }

    @Test fun shortTakeStopFailureDoesNotPreventCancellationCleanup() {
        val recorder = FakeRecorder()
        val backend = prepared(recorder)
        backend.start()
        recorder.failures["stop"] = RuntimeException("not enough samples")
        backend.cancel()
        backend.release()
        assertEquals(listOf("prepare", "start", "stop", "reset", "release"), recorder.calls)
    }

    @Test fun failedSavePropagatesErrorReleasesAndPreservesTemporaryData() {
        val directory = Files.createTempDirectory("m4a-backend-").toFile()
        try {
            val output = File(directory, "recording-one.m4a.part")
            output.writeBytes(byteArrayOf(1, 2, 3))
            val recorder = FakeRecorder()
            val backend = M4aRecordingBackend { recorder }
            backend.prepare(output)
            backend.start()
            val failure = RuntimeException("stop failed")
            recorder.failures["stop"] = failure
            assertSame(failure, assertThrows(RuntimeException::class.java) { backend.stop() })
            backend.release()
            assertArrayEquals(byteArrayOf(1, 2, 3), output.readBytes())
            assertEquals(listOf(output.name), directory.list()!!.toList())
            assertEquals(listOf("prepare", "start", "stop", "reset", "release"), recorder.calls)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test fun preparingOrStartingFailureReleasesPartialRecorder() {
        for (operation in listOf("prepare", "start")) {
            val recorder = FakeRecorder()
            val failure = RuntimeException("$operation failed")
            recorder.failures[operation] = failure
            val backend = M4aRecordingBackend { recorder }
            assertSame(failure, assertThrows(RuntimeException::class.java) {
                backend.prepare(File("recording-one.m4a.part"))
                backend.start()
            })
            backend.release()
            assertEquals(listOf("reset", "release"), recorder.calls.takeLast(2))
            assertEquals(1, recorder.calls.count { it == "release" })
        }
    }

    @Test fun pauseOrResumeFailureCanBeReleasedWithoutTryingToSave() {
        for (operation in listOf("pause", "resume")) {
            val recorder = FakeRecorder()
            val backend = prepared(recorder)
            backend.start()
            if (operation == "resume") backend.pause()
            val failure = RuntimeException("$operation failed")
            recorder.failures[operation] = failure
            assertSame(failure, assertThrows(RuntimeException::class.java) {
                if (operation == "pause") backend.pause() else backend.resume()
            })
            backend.release()
            backend.release()
            assertFalse(recorder.calls.contains("stop"))
            assertEquals(listOf("reset", "release"), recorder.calls.takeLast(2))
            assertEquals(1, recorder.calls.count { it == "release" })
        }
    }

    @Test fun successfulStopAndCancelLeaveFileCommitOrDeletionToTheService() {
        val directory = Files.createTempDirectory("m4a-backend-output-").toFile()
        try {
            for (cancelled in listOf(false, true)) {
                val output = File(directory, "recording-one.m4a.part")
                output.writeBytes(byteArrayOf(4, 5, 6))
                val backend = M4aRecordingBackend { FakeRecorder() }
                backend.prepare(output)
                backend.start()
                if (cancelled) backend.cancel() else backend.stop()
                assertArrayEquals(byteArrayOf(4, 5, 6), output.readBytes())
                assertEquals(listOf(output.name), directory.list()!!.toList())
            }
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test fun cleanupFailureDoesNotReplaceTheOperationFailure() {
        val recorder = FakeRecorder()
        val failure = RuntimeException("prepare failed")
        val cleanupFailure = RuntimeException("release failed")
        recorder.failures["prepare"] = failure
        recorder.failures["release"] = cleanupFailure
        val backend = M4aRecordingBackend { recorder }
        assertSame(failure, assertThrows(RuntimeException::class.java) {
            backend.prepare(File("recording-one.m4a.part"))
        })
        assertArrayEquals(arrayOf(cleanupFailure), failure.suppressed)
        backend.release()
        assertEquals(1, recorder.calls.count { it == "release" })
    }

    @Test fun resetFailureStillReleasesOnceWithoutFinalizing() {
        val recorder = FakeRecorder()
        val backend = prepared(recorder)
        backend.start()
        recorder.failures["reset"] = RuntimeException("reset failed")
        backend.release()
        backend.release()
        assertEquals(listOf("prepare", "start", "reset", "release"), recorder.calls)
    }

    @Test fun invalidOrderingOrOutputNeverStartsAnotherCapture() {
        val recorder = FakeRecorder()
        var created = 0
        val backend = M4aRecordingBackend { created++; recorder }
        assertThrows(IllegalStateException::class.java) { backend.start() }
        assertThrows(IllegalStateException::class.java) { backend.pause() }
        assertThrows(IllegalStateException::class.java) { backend.resume() }
        assertThrows(IllegalStateException::class.java) { backend.stop() }
        assertThrows(IllegalArgumentException::class.java) { backend.prepare(File("one.mp3.part")) }
        assertEquals(0, created)
        backend.prepare(File("recording-one.m4a.part"))
        assertThrows(IllegalStateException::class.java) { backend.prepare(File("recording-two.m4a.part")) }
        backend.start()
        assertThrows(IllegalStateException::class.java) { backend.start() }
        assertEquals(1, created)
        assertEquals(listOf("prepare", "start"), recorder.calls)
        backend.release()
        assertThrows(IllegalStateException::class.java) { backend.resume() }
    }

    @Test fun factoryRejectsMp3WithoutCreatingOrFallingBackToM4a() {
        val recorder = FakeRecorder()
        val m4a = M4aRecordingBackend { recorder }
        var created = 0
        val factory = RecordingBackendFactory(createM4a = { created++; m4a })
        assertThrows(UnsupportedOperationException::class.java) { factory.create(RecordingFormat.MP3) }
        assertEquals(0, created)
        assertSame(m4a, factory.create(RecordingFormat.M4A))
        assertEquals(1, created)
        assertTrue(recorder.calls.isEmpty())
        assertTrue(RecordingBackendFactory().create(RecordingFormat.M4A) is M4aRecordingBackend)
    }

    private fun prepared(recorder: FakeRecorder): M4aRecordingBackend =
        M4aRecordingBackend { recorder }.also { it.prepare(File("recording-one.m4a.part")) }

    private class FakeRecorder : M4aRecorder {
        val calls = mutableListOf<String>()
        val failures = mutableMapOf<String, RuntimeException>()
        var output: File? = null

        private fun record(operation: String) {
            calls += operation
            failures[operation]?.let { throw it }
        }

        override fun prepare(temporaryFile: File) { output = temporaryFile; record("prepare") }
        override fun start() = record("start")
        override fun pause() = record("pause")
        override fun resume() = record("resume")
        override fun stop() = record("stop")
        override fun reset() = record("reset")
        override fun release() = record("release")
    }
}
