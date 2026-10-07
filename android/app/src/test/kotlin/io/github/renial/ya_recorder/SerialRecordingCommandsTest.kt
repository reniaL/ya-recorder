package io.github.renial.ya_recorder

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class SerialRecordingCommandsTest {
    @Test fun commandsRunInOrderOnOneWorkerInsteadOfTheCallerThread() {
        val commands = SerialRecordingCommands()
        val calls = CopyOnWriteArrayList<String>()
        val threads = CopyOnWriteArrayList<Thread>()
        val done = CountDownLatch(1)
        try {
            for (action in listOf("prepare", "start", "pause", "resume", "stop")) {
                commands.submit { calls += action; threads += Thread.currentThread() }
            }
            commands.submit { done.countDown() }
            assertTrue(done.await(2, TimeUnit.SECONDS))
            assertEquals(listOf("prepare", "start", "pause", "resume", "stop"), calls)
            assertEquals(1, threads.distinct().size)
            assertNotSame(Thread.currentThread(), threads.first())
        } finally { commands.close {} }
    }

    @Test fun destructionSkipsQueuedCommandsAndReleasesAfterTheActiveWrite() {
        val commands = SerialRecordingCommands()
        val calls = CopyOnWriteArrayList<String>()
        val writing = CountDownLatch(1)
        val finishWrite = CountDownLatch(1)
        val cleaned = CountDownLatch(1)
        commands.submit {
            writing.countDown()
            check(finishWrite.await(2, TimeUnit.SECONDS))
            calls += "write-finished"
            if (!commands.isClosed) calls += "commit"
        }
        assertTrue(writing.await(2, TimeUnit.SECONDS))
        commands.submit { calls += "new-session" }
        commands.close { calls += "release"; cleaned.countDown() }
        commands.close { calls += "duplicate-release" }
        commands.submit { calls += "late-callback" }
        assertTrue(commands.isClosed)
        assertEquals(1L, cleaned.count)
        finishWrite.countDown()
        assertTrue(cleaned.await(2, TimeUnit.SECONDS))
        assertEquals(listOf("write-finished", "release"), calls)
    }
}
