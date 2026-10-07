package io.github.renial.ya_recorder

import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

internal interface PcmSource {
    fun onCaptureThread() {}
    fun start()
    /** Nonblocking mono PCM16 read: 0 means no samples ready, negative is error. */
    fun read(buffer: ShortArray): Int
    fun stop()
    fun release()
}

internal interface Mp3Encoder {
    fun open(output: File)
    fun encode(samples: ShortArray)
    fun finish()
    fun close()
}

internal data class Mp3Config(
    val sampleRate: Int = 44100,
    val chunkSamples: Int = 4410,
    val queueBlocks: Int = 16,
    val joinTimeoutMs: Long = 5000,
) {
    init {
        require(sampleRate == 44100 && chunkSamples in 1..4410)
        require(queueBlocks in 1..16 && joinTimeoutMs > 0)
    }
}

/** Candidate MP3 pipeline. Public commands run on the service control worker.
 * The capture lock defines pause/stop sample boundaries. Only the encoder
 * thread owns JNI handles and file writes; no complete PCM file is staged.
 */
class Mp3RecordingBackend internal constructor(
    private val createSource: () -> PcmSource,
    private val createEncoder: () -> Mp3Encoder,
    private val config: Mp3Config = Mp3Config(),
) : RecordingBackend {
    constructor() : this({ AndroidPcmSource() }, { AndroidMp3Encoder() })

    override val format = RecordingFormat.MP3
    override val elapsedMs: Long get() = acceptedSamples.get() * 1000 / config.sampleRate
    internal val acceptedSamples = AtomicLong(0)
    internal val encodedSamples = AtomicLong(0)
    internal val queueHighWater = AtomicInteger(0)
    private val queue = ArrayBlockingQueue<ShortArray>(config.queueBlocks)
    private val captureLock = Object()
    private val shutdown = AtomicBoolean(false)
    private val abort = AtomicBoolean(false)
    private val captureDone = AtomicBoolean(false)
    private val failure = AtomicReference<Throwable?>(null)
    private val cleanupFailure = AtomicReference<Throwable?>(null)
    private val pending = ShortArray(config.chunkSamples)
    private var pendingSamples = 0
    @Volatile private var failureListener: ((Throwable) -> Unit)? = null
    private var source: PcmSource? = null
    private var sourceRunning = false
    private var capturing = false
    private var captureThread: Thread? = null
    private var encoderThread: Thread? = null
    @Volatile private var finishRequested = false
    private var state = State.NEW

    override fun setFailureListener(listener: (Throwable) -> Unit) { failureListener = listener }

    @Synchronized override fun prepare(temporaryFile: File) {
        check(state == State.NEW) { "MP3 backend has already been prepared" }
        require(temporaryFile.name.endsWith(".mp3.part")) { "Invalid MP3 temporary path" }
        try {
            source = createSource()
            val ready = CountDownLatch(1)
            encoderThread = Thread({ encodeLoop(temporaryFile, ready) }, "rec07-mp3-encode").apply {
                isDaemon = true
                start()
            }
            check(ready.await(config.joinTimeoutMs, TimeUnit.MILLISECONDS)) { "MP3 encoder initialization timed out" }
            throwIfFailed()
            state = State.PREPARED
        } catch (error: Throwable) {
            recordFailure(error)
            cleanupAfterFailure(error)
            throw operationError(error)
        }
    }

    @Synchronized override fun start() {
        check(state == State.PREPARED) { "MP3 backend is not prepared" }
        try {
            throwIfFailed()
            synchronized(captureLock) {
                checkNotNull(source).start()
                sourceRunning = true
                capturing = true
            }
            captureThread = Thread({ captureLoop() }, "rec07-mp3-capture").apply {
                isDaemon = true
                start()
            }
            state = State.RECORDING
        } catch (error: Throwable) {
            recordFailure(error)
            cleanupAfterFailure(error)
            throw operationError(error)
        }
    }

    @Synchronized override fun pause() {
        check(state == State.RECORDING) { "MP3 backend is not recording" }
        throwIfFailed()
        synchronized(captureLock) {
            capturing = false
            flushPendingLocked()
            stopSourceLocked()
        }
        state = State.PAUSED
    }

    @Synchronized override fun resume() {
        check(state == State.PAUSED) { "MP3 backend is not paused" }
        throwIfFailed()
        synchronized(captureLock) {
            checkNotNull(source).start()
            sourceRunning = true
            capturing = true
            captureLock.notifyAll()
        }
        state = State.RECORDING
    }

    @Synchronized override fun stop() {
        if (state == State.RELEASED) { throwIfFailed(); return }
        check(state == State.RECORDING || state == State.PAUSED) { "MP3 backend has not started" }
        try {
            finishRequested = true
            endCapture()
            awaitThreads()
            throwIfFailed()
            check(acceptedSamples.get() > 0 && acceptedSamples.get() == encodedSamples.get()) { "MP3 recording is incomplete" }
        } catch (error: Throwable) {
            recordFailure(error)
            cleanupAfterFailure(error)
            throw operationError(error)
        }
        state = State.RELEASED
    }

    @Synchronized override fun cancel() = release()

    @Synchronized override fun release() {
        abort.set(true)
        try {
            endCapture()
            awaitThreads()
            state = State.RELEASED
            cleanupFailure.get()?.let { throw operationError(it) }
        } catch (error: Throwable) {
            recordFailure(error)
            throw operationError(error)
        }
    }

    private fun endCapture() {
        shutdown.set(true)
        synchronized(captureLock) {
            capturing = false
            try {
                if (finishRequested && !abort.get()) flushPendingLocked()
                stopSourceLocked()
            } catch (error: Throwable) {
                cleanupFailure.compareAndSet(null, error)
                recordFailure(error)
            }
            captureLock.notifyAll()
        }
        if (captureThread == null) {
            releaseSource()
            captureDone.set(true)
        }
    }

    private fun captureLoop() {
        val buffer = ShortArray(config.chunkSamples)
        try {
            checkNotNull(source).onCaptureThread()
            while (!shutdown.get()) {
                synchronized(captureLock) {
                    if (shutdown.get()) return@synchronized
                    if (!capturing) {
                        captureLock.wait(100)
                    } else {
                        val size = checkNotNull(source).read(buffer)
                        check(size in 0..buffer.size) { "Microphone read failed: $size" }
                        if (size == 0) captureLock.wait(5)
                        else {
                            var offset = 0
                            while (offset < size) {
                                val count = minOf(size - offset, pending.size - pendingSamples)
                                buffer.copyInto(pending, pendingSamples, offset, offset + count)
                                pendingSamples += count
                                offset += count
                                if (pendingSamples == pending.size) flushPendingLocked()
                            }
                        }
                    }
                }
            }
        } catch (error: Throwable) {
            recordFailure(error)
        } finally {
            releaseSource()
            captureDone.set(true)
        }
    }

    private fun encodeLoop(output: File, ready: CountDownLatch) {
        var encoder: Mp3Encoder? = null
        try {
            encoder = createEncoder()
            encoder.open(output)
            ready.countDown()
            while (!abort.get() && (!captureDone.get() || queue.isNotEmpty())) {
                val block = queue.poll(50, TimeUnit.MILLISECONDS) ?: continue
                if (abort.get()) break
                encoder.encode(block)
                encodedSamples.addAndGet(block.size.toLong())
            }
            if (!abort.get() && finishRequested && failure.get() == null) {
                check(acceptedSamples.get() > 0 && acceptedSamples.get() == encodedSamples.get()) { "No complete MP3 audio samples" }
                encoder.finish()
            }
        } catch (error: Throwable) {
            recordFailure(error)
        } finally {
            try { encoder?.close() }
            catch (error: Throwable) { cleanupFailure.compareAndSet(null, error); recordFailure(error) }
            ready.countDown()
        }
    }

    private fun releaseSource() {
        synchronized(captureLock) {
            val activeSource = source
            source = null
            try { if (sourceRunning) activeSource?.stop() }
            catch (error: Throwable) { cleanupFailure.compareAndSet(null, error); recordFailure(error) }
            finally {
                sourceRunning = false
                try { activeSource?.release() }
                catch (error: Throwable) { cleanupFailure.compareAndSet(null, error); recordFailure(error) }
            }
        }
    }

    private fun stopSourceLocked() {
        if (!sourceRunning) return
        try { source?.stop() } finally { sourceRunning = false }
    }

    private fun flushPendingLocked() {
        if (pendingSamples == 0) return
        check(queue.offer(pending.copyOf(pendingSamples))) { "PCM queue overflow; MP3 recording is incomplete" }
        acceptedSamples.addAndGet(pendingSamples.toLong())
        pendingSamples = 0
        queueHighWater.accumulateAndGet(queue.size, ::maxOf)
    }

    private fun awaitThreads() {
        for (thread in listOfNotNull(captureThread, encoderThread)) {
            thread.join(config.joinTimeoutMs)
            check(!thread.isAlive) { "MP3 ${thread.name} did not stop; temporary data retained" }
        }
    }

    private fun recordFailure(error: Throwable) {
        if (!failure.compareAndSet(null, error)) return
        abort.set(true)
        shutdown.set(true)
        synchronized(captureLock) { captureLock.notifyAll() }
        failureListener?.invoke(error)
    }

    private fun cleanupAfterFailure(error: Throwable) {
        try { release() } catch (cleanup: Throwable) { if (cleanup !== error) error.addSuppressed(cleanup) }
    }

    private fun throwIfFailed() { failure.get()?.let { throw operationError(it) } }
    private fun operationError(error: Throwable): Exception =
        if (error is Exception) error else IllegalStateException("MP3 native encoder unavailable: ${error.message}", error)

    private enum class State { NEW, PREPARED, RECORDING, PAUSED, RELEASED }
}
