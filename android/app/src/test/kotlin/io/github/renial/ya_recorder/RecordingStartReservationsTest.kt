package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Test

class RecordingStartReservationsTest {
    private fun idle() = mapOf<String, Any?>("state" to "idle", "format" to null, "sessionId" to null)

    @Test fun queuedStartMasksIdleBeforeTheWorkerRuns() {
        val gate = RecordingStartReservations()
        val token = gate.reserve("aac")
        val queued = gate.status { idle() }
        assertEquals("preparing", queued["state"])
        assertEquals("aac", queued["format"])
        assertEquals(false, queued["canResume"])
        gate.complete(token)
        assertEquals("idle", gate.status { idle() }["state"])
    }

    @Test fun completionReadsLatestNativeStateAndPreservesActiveSessions() {
        val gate = RecordingStartReservations()
        val token = gate.reserve("mp3")
        var native: Map<String, Any?> = idle()
        assertEquals("preparing", gate.status { native }["state"])
        native = mapOf("state" to "recording", "format" to "mp3", "sessionId" to "one")
        assertSame(native, gate.status { native })
        gate.complete(token)
        assertSame(native, gate.status { native })
    }

    @Test fun failedLaunchAndSkippedCommandsReleaseOnlyTheirOwnReservations() {
        val gate = RecordingStartReservations()
        val oldService = gate.reserve("aac")
        val newService = gate.reserve("mp3")
        gate.complete(oldService)
        gate.complete(oldService)
        gate.complete(null)
        gate.complete("unknown")
        assertEquals("mp3", gate.status { idle() }["format"])
        gate.complete(newService)
        assertEquals("idle", gate.status { idle() }["state"])
    }

    @Test fun pendingStartAlsoMasksPreviousFailedState() {
        val gate = RecordingStartReservations()
        val failed = mapOf<String, Any?>("state" to "failed", "sessionId" to null)
        val token = gate.reserve("aac")
        assertEquals("preparing", gate.status { failed }["state"])
        gate.complete(token)
        assertSame(failed, gate.status { failed })
    }
}
