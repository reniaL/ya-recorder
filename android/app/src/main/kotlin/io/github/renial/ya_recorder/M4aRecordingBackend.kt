package io.github.renial.ya_recorder

import java.io.File

/** Test seam for the Android recorder; one instance writes one M4A file. */
internal interface M4aRecorder {
    fun prepare(temporaryFile: File)
    fun start()
    fun pause()
    fun resume()
    fun stop()
    fun reset()
    fun release()
}

class M4aRecordingBackend internal constructor(
    private val createRecorder: () -> M4aRecorder,
) : RecordingBackend {
    constructor() : this({ AndroidM4aRecorder() })

    override val format = RecordingFormat.M4A
    private var recorder: M4aRecorder? = null
    private var state = State.NEW

    override fun prepare(temporaryFile: File) {
        check(state == State.NEW) { "The recording backend has already been prepared" }
        require(temporaryFile.name.endsWith(".${format.extension}.part")) { "Invalid M4A temporary path" }
        try {
            recorder = createRecorder()
            requireRecorder().prepare(temporaryFile)
            state = State.PREPARED
        } catch (error: Exception) {
            releaseAfterFailure(error)
            throw error
        }
    }

    override fun start() {
        check(state == State.PREPARED) { "The recording backend is not prepared" }
        try {
            requireRecorder().start()
            state = State.RECORDING
        } catch (error: Exception) {
            releaseAfterFailure(error)
            throw error
        }
    }

    override fun pause() {
        check(state == State.RECORDING) { "The recording backend is not recording" }
        requireRecorder().pause()
        state = State.PAUSED
    }

    override fun resume() {
        check(state == State.PAUSED) { "The recording backend is not paused" }
        requireRecorder().resume()
        state = State.RECORDING
    }

    override fun stop() {
        if (state == State.RELEASED) return
        check(state == State.RECORDING || state == State.PAUSED) { "The recording backend has not started" }
        try {
            requireRecorder().stop()
        } catch (error: Exception) {
            releaseAfterFailure(error)
            throw error
        }
        release()
    }

    override fun cancel() {
        try {
            if (state == State.RECORDING || state == State.PAUSED) {
                requireRecorder().stop()
            }
        } catch (_: RuntimeException) {
            // A short take may not contain enough samples to stop cleanly.
        } finally {
            release()
        }
    }

    override fun release() {
        val activeRecorder = recorder
        recorder = null
        state = State.RELEASED
        if (activeRecorder == null) return
        try {
            activeRecorder.reset()
        } catch (_: RuntimeException) {
            // reset can fail after a platform recorder error; still release it.
        } finally {
            activeRecorder.release()
        }
    }

    private fun requireRecorder(): M4aRecorder =
        checkNotNull(recorder) { "The recording backend has no recorder" }

    private fun releaseAfterFailure(error: Exception) {
        try {
            release()
        } catch (cleanupError: Exception) {
            if (cleanupError !== error) error.addSuppressed(cleanupError)
        }
    }

    private enum class State { NEW, PREPARED, RECORDING, PAUSED, RELEASED }
}
