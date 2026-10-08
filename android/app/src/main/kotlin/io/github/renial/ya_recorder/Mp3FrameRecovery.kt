package io.github.renial.ya_recorder

import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile

/** Conservative recovery for this encoder's MPEG-1 Layer III, 44.1 kHz mono.
 * Never searches past a damaged frame or modifies the original .part file.
 * A complete frame prefix still requires a full independent media decode.
 */
internal object Mp3FrameRecovery {
    fun copyCompletePrefix(source: File, target: File) {
        check(source.isFile && source.canonicalFile != target.canonicalFile)
        RandomAccessFile(source, "r").use { input ->
            var end = 0L
            var frames = 0
            while (end + 4 <= input.length()) {
                input.seek(end)
                val header = input.readInt()
                if ((header ushr 21) != 0x7ff || (header ushr 19 and 3) != 3 ||
                    (header ushr 17 and 3) != 1 || (header ushr 10 and 3) != 0 ||
                    (header ushr 6 and 3) != 3) break
                val bitrate = intArrayOf(0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0)[header ushr 12 and 15]
                if (bitrate == 0) break
                val size = 144000 * bitrate / 44100 + (header ushr 9 and 1)
                if (end + size > input.length()) break
                end += size
                frames++
            }
            check(frames >= 2) { "No recoverable MP3 frame prefix" }
            input.seek(0)
            FileOutputStream(target).use { output ->
                val buffer = ByteArray(8192)
                var remaining = end
                while (remaining > 0) {
                    val size = input.read(buffer, 0, minOf(remaining, buffer.size.toLong()).toInt())
                    check(size > 0)
                    output.write(buffer, 0, size)
                    remaining -= size
                }
                output.fd.sync()
            }
        }
        // A stale Info/Xing tag may describe the original, longer recording.
        // Disable that hint in the copy; duration must come from actual decoding.
        RandomAccessFile(target, "rw").use { file ->
            val header = file.readInt()
            file.seek((21 + if (header and 0x10000 == 0) 2 else 0).toLong())
            val tag = file.readInt()
            if (tag == 0x496e666f || tag == 0x58696e67) {
                file.seek((21 + if (header and 0x10000 == 0) 2 else 0).toLong())
                file.writeInt(0)
            }
            file.fd.sync()
        }
    }
}
