package io.github.renial.ya_recorder.mp3prototype

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Debug
import android.os.Process
import android.os.SystemClock
import io.github.renial.ya_recorder.mp3.LameEncoder
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.sin

internal class PrototypeRun(private val context: Context, private val config: PrototypeConfig, private val directory: File) {
    private val stopRequested = AtomicBoolean(false)
    private val captureDone = AtomicBoolean(false)
    private val failure = AtomicReference<Throwable?>(null)
    private val acceptedSamples = AtomicLong(0)
    private val encodedSamples = AtomicLong(0)
    private val queue = PcmQueue(PrototypeConfig.QUEUE_BLOCKS, PrototypeConfig.CHUNK_SAMPLES)
    private val captureStoppedNs = AtomicLong(0)
    private val encoderFinishedNs = AtomicLong(0)
    private var startedNs = 0L
    private var startedCpuMs = 0L
    @Volatile private var maxEncodeNs = 0L
    @Volatile private var encodeCpuMs = 0L
    @Volatile private var finishMs = 0L
    @Volatile private var lameVersion = "unavailable"
    private val part = File(directory, "audio.mp3.part")
    private val output = File(directory, "audio.mp3")

    fun requestStop() { stopRequested.set(true) }

    fun execute(): JSONObject {
        check(directory.mkdirs() || directory.isDirectory)
        startedNs = SystemClock.elapsedRealtimeNanos()
        startedCpuMs = Process.getElapsedCpuTime()
        val encoderReady = java.util.concurrent.CountDownLatch(1)
        val encoder = Thread({
            val cpuStart = SystemClock.currentThreadTimeMillis()
            var native: LameEncoder? = null
            var handle = 0L
            try {
                native = LameEncoder()
                lameVersion = native.version()
                handle = native.open(part.absolutePath, config.bitrate, config.quality)
                check(handle != 0L) { "LAME initialization failed" }
                encoderReady.countDown()
                while (!captureDone.get() || !queue.isEmpty()) {
                    if (failure.get() != null) break
                    val block = queue.poll() ?: continue
                    val before = SystemClock.elapsedRealtimeNanos()
                    if (config.encoderDelayMs > 0) Thread.sleep(config.encoderDelayMs.toLong())
                    check(native.encode(handle, block, block.size) >= 0) { "MP3 encoding/write failed" }
                    encodedSamples.addAndGet(block.size.toLong())
                    maxEncodeNs = maxOf(maxEncodeNs, SystemClock.elapsedRealtimeNanos() - before)
                }
                if (failure.get() == null) {
                    val before = SystemClock.elapsedRealtimeNanos()
                    check(native.finish(handle) == 0) { "MP3 flush/tag/sync failed" }
                    finishMs = (SystemClock.elapsedRealtimeNanos() - before) / 1000000
                }
            } catch (error: Throwable) {
                failure.compareAndSet(null, error)
                stopRequested.set(true)
            } finally {
                if (handle != 0L) native?.close(handle)
                encodeCpuMs = SystemClock.currentThreadTimeMillis() - cpuStart
                encoderFinishedNs.set(SystemClock.elapsedRealtimeNanos())
                encoderReady.countDown()
            }
        }, "rec07-encode")
        encoder.start()
        encoderReady.await()
        val capture = Thread({
            try {
                Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                if (failure.get() == null) capture()
            } catch (error: Throwable) {
                failure.compareAndSet(null, error)
                stopRequested.set(true)
            } finally {
                captureStoppedNs.set(SystemClock.elapsedRealtimeNanos())
                captureDone.set(true)
            }
        }, "rec07-capture")
        capture.start()
        while (capture.isAlive || encoder.isAlive) {
            try { writeJson("progress.json", metrics().put("status", "running")) }
            catch (error: Throwable) {
                failure.compareAndSet(null, error)
                stopRequested.set(true)
            }
            Thread.sleep(1000)
        }
        capture.join()
        encoder.join()
        var validation: JSONObject? = null
        try {
            if (failure.get() == null) {
                check(acceptedSamples.get() > 0 && acceptedSamples.get() == encodedSamples.get())
                validation = MediaValidation.decode(part)
                val audioMs = acceptedSamples.get() * 1000 / PrototypeConfig.SAMPLE_RATE
                check(kotlin.math.abs(validation.getLong("mediaDurationMs") - audioMs) <= 100) { "MP3 duration mismatch" }
                // Android codecs may include encoder delay/padding rather than trim it.
                check(kotlin.math.abs(validation.getLong("decodedSamples") - acceptedSamples.get()) <= PrototypeConfig.CHUNK_SAMPLES) {
                    "Decoded audio length does not match accepted PCM"
                }
                if (config.tone) check(validation.getInt("decodedPeak") > 1000) { "Test tone was not decoded" }
                check(part.renameTo(output)) { "Unable to finalize prototype output" }
            }
        } catch (error: Throwable) {
            failure.compareAndSet(null, error)
        }
        val result = metrics().put("status", if (failure.get() == null) "passed" else "failed")
            .put("error", failure.get()?.let { "${it.javaClass.simpleName}: ${it.message}" } ?: JSONObject.NULL)
            .put("validation", validation ?: JSONObject.NULL)
            .put("outputBytes", if (output.exists()) output.length() else part.length())
            .put("output", if (failure.get() == null) "audio.mp3" else "audio.mp3.part")
        writeJson("result.json", result)
        return result
    }

    private fun capture() {
        val sampleRate = PrototypeConfig.SAMPLE_RATE
        val chunk = PrototypeConfig.CHUNK_SAMPLES
        val target = config.seconds.toLong() * sampleRate
        var recorder: AudioRecord? = null
        try {
            if (!config.tone) {
                if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    throw SecurityException("Microphone permission is not granted")
                }
                val minimum = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                check(minimum > 0) { "Unsupported AudioRecord configuration: $minimum" }
                recorder = AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum * 2, chunk * 4))
                check(recorder.state == AudioRecord.STATE_INITIALIZED) { "AudioRecord initialization failed" }
                recorder.startRecording()
                check(recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            }
            val clockStart = SystemClock.elapsedRealtimeNanos()
            while (!stopRequested.get() && acceptedSamples.get() < target) {
                val count = minOf(chunk.toLong(), target - acceptedSamples.get()).toInt()
                val block = ShortArray(count)
                val size = if (config.tone) {
                    val start = acceptedSamples.get()
                    for (i in block.indices) block[i] = (12000 * sin(2 * Math.PI * 440 * (start + i) / sampleRate)).toInt().toShort()
                    // Synthetic input is paced: it exercises the same queue for an hour of wall time.
                    val due = clockStart + (start + count) * 1000000000L / sampleRate
                    val waitNs = due - SystemClock.elapsedRealtimeNanos()
                    if (waitNs > 0) Thread.sleep(waitNs / 1000000, (waitNs % 1000000).toInt())
                    count
                } else checkNotNull(recorder).read(block, 0, count, AudioRecord.READ_BLOCKING)
                check(size > 0) { "AudioRecord read failed: $size" }
                check(queue.offer(if (size == count) block else block.copyOf(size))) { "PCM queue overflow; recording is incomplete" }
                acceptedSamples.addAndGet(size.toLong())
            }
        } finally {
            try { if (recorder?.recordingState == AudioRecord.RECORDSTATE_RECORDING) recorder.stop() }
            finally { recorder?.release() }
        }
    }

    private fun metrics(): JSONObject = JSONObject()
        .put("source", if (config.tone) "paced-tone" else "microphone")
        .put("requestedSeconds", config.seconds).put("sampleRate", PrototypeConfig.SAMPLE_RATE)
        .put("channels", 1).put("bitrateKbps", config.bitrate).put("quality", config.quality)
        .put("encoderDelayMs", config.encoderDelayMs).put("lameVersion", lameVersion)
        .put("acceptedSamples", acceptedSamples.get()).put("encodedSamples", encodedSamples.get())
        .put("acceptedDurationMs", acceptedSamples.get() * 1000 / PrototypeConfig.SAMPLE_RATE)
        .put("queueCapacity", PrototypeConfig.QUEUE_BLOCKS).put("queueHighWater", queue.highWaterMark)
        .put("wallMs", (SystemClock.elapsedRealtimeNanos() - startedNs) / 1000000)
        .put("encodeCpuMs", encodeCpuMs).put("maxEncodeBlockMs", maxEncodeNs / 1000000.0)
        .put("processCpuMs", Process.getElapsedCpuTime() - startedCpuMs)
        .put("flushSyncMs", finishMs)
        .put("drainAndFinishMs", if (captureStoppedNs.get() == 0L || encoderFinishedNs.get() == 0L) JSONObject.NULL else
            maxOf(0L, encoderFinishedNs.get() - captureStoppedNs.get()) / 1000000)
        .put("pssKb", Debug.getPss()).put("nativeHeapBytes", Debug.getNativeHeapAllocatedSize())
        .put("javaHeapBytes", Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())
        .put("device", Build.MODEL).put("sdk", Build.VERSION.SDK_INT).put("abis", Build.SUPPORTED_ABIS.joinToString())

    private fun writeJson(name: String, json: JSONObject) {
        val staged = File(directory, "$name.tmp")
        staged.writeText(json.toString(2))
        check(staged.renameTo(File(directory, name))) { "Unable to write prototype report" }
    }
}
