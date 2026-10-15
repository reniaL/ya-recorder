package io.github.renial.ya_recorder

import java.io.InputStream
import java.io.OutputStream
import java.io.IOException
import java.util.concurrent.CancellationException

/** Bounded memory, no seek/file-path assumptions, cancellation at IO boundaries. */
internal object BackupStreamCopy {
    const val MAX_BYTES = 64L * 1024 * 1024 * 1024

    fun copy(
        input: InputStream,
        output: OutputStream,
        cancelled: () -> Boolean,
        progress: (Long) -> Unit,
        limit: Long = MAX_BYTES,
    ): Long {
        val buffer = ByteArray(64 * 1024)
        var copied = 0L
        fun check() { if (cancelled()) throw CancellationException("Backup cancelled") }
        while (true) {
            check()
            val count = input.read(buffer)
            check()
            if (count < 0) break
            if (count == 0) continue
            if (count > limit - copied) throw IOException("Backup exceeds staging limit")
            output.write(buffer, 0, count)
            copied += count
            progress(copied)
        }
        check()
        output.flush()
        check()
        return copied
    }
}
