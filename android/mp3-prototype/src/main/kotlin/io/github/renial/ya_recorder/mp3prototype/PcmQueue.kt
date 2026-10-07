package io.github.renial.ya_recorder.mp3prototype

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit

internal class PcmQueue(capacity: Int, private val maxSamples: Int) {
    private val queue = ArrayBlockingQueue<ShortArray>(capacity)
    @Volatile var highWaterMark = 0
        private set

    // Never block the microphone reader or silently drop a block on overflow.
    @Synchronized fun offer(samples: ShortArray): Boolean {
        require(samples.isNotEmpty() && samples.size <= maxSamples)
        if (!queue.offer(samples)) return false
        highWaterMark = maxOf(highWaterMark, queue.size)
        return true
    }

    fun poll(): ShortArray? = queue.poll(100, TimeUnit.MILLISECONDS)
    fun isEmpty(): Boolean = queue.isEmpty()
}
