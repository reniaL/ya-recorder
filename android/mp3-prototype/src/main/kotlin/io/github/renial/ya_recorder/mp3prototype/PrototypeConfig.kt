package io.github.renial.ya_recorder.mp3prototype

internal data class PrototypeConfig(
    val seconds: Int = 10,
    val tone: Boolean = false,
    val bitrate: Int = 64,
    val quality: Int = 5,
    val encoderDelayMs: Int = 0,
) {
    init {
        require(seconds in 1..7200)
        require(bitrate == 64 || bitrate == 96)
        require(quality == 2 || quality == 5)
        require(encoderDelayMs in 0..500)
    }

    companion object {
        const val SAMPLE_RATE = 44100
        const val CHUNK_SAMPLES = 4410
        const val QUEUE_BLOCKS = 16
    }
}
