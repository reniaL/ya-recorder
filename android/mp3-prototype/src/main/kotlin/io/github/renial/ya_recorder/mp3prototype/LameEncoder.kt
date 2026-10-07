package io.github.renial.ya_recorder.mp3prototype

// Called only on the encoding thread; the handle never crosses thread ownership.
internal class LameEncoder {
    external fun open(path: String, bitrate: Int, quality: Int): Long
    external fun encode(handle: Long, pcm: ShortArray, count: Int): Int
    external fun finish(handle: Long): Int
    external fun close(handle: Long)
    external fun version(): String

    companion object { init { System.loadLibrary("rec07_lame") } }
}
