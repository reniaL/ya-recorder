package io.github.renial.ya_recorder.mp3prototype

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class PcmQueueTest {
    @Test fun overflowDoesNotDropOrReplaceAcceptedAudio() {
        val queue = PcmQueue(2, 10)
        assertTrue(queue.offer(shortArrayOf(1, 2)))
        assertTrue(queue.offer(shortArrayOf(3)))
        assertFalse(queue.offer(shortArrayOf(4)))
        assertEquals(2, queue.highWaterMark)
        assertArrayEquals(shortArrayOf(1, 2), queue.poll())
        assertTrue(queue.offer(shortArrayOf(5)))
        assertArrayEquals(shortArrayOf(3), queue.poll())
        assertArrayEquals(shortArrayOf(5), queue.poll())
        assertTrue(queue.isEmpty())
    }

    @Test fun partialFinalBlockAndConcurrentDrainPreserveEverySample() {
        val queue = PcmQueue(16, 10)
        val complete = CountDownLatch(1)
        val output = mutableListOf<Short>()
        val consumer = Thread {
            repeat(100) { output.addAll(checkNotNull(queue.poll()).toList()) }
            complete.countDown()
        }
        consumer.start()
        for (i in 0 until 100) {
            val block = shortArrayOf(i.toShort())
            while (!queue.offer(block)) Thread.yield()
        }
        assertTrue(complete.await(5, TimeUnit.SECONDS))
        consumer.join()
        assertEquals((0 until 100).map { it.toShort() }, output)
        assertTrue(queue.highWaterMark <= 16)
    }

    @Test(expected = IllegalArgumentException::class)
    fun oversizedBlocksCannotExceedMemoryBound() { PcmQueue(2, 10).offer(ShortArray(11)) }

    @Test(expected = IllegalArgumentException::class)
    fun emptyBlocksAreRejected() { PcmQueue(2, 10).offer(shortArrayOf()) }

    @Test(expected = IllegalArgumentException::class)
    fun unsupportedBitrateIsRejected() { PrototypeConfig(bitrate = 128) }

    @Test(expected = IllegalArgumentException::class)
    fun invalidDurationIsRejected() { PrototypeConfig(seconds = 0) }
}
