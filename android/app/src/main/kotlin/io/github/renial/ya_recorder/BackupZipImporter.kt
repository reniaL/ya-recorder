package io.github.renial.ya_recorder

import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import java.util.zip.CRC32
import java.util.zip.ZipFile

internal data class BackupImportEntry(val path: String, val size: Long, val sha256: String)

/** Untrusted ZIP adapter. Bound and inspect the raw directory BEFORE ZipFile allocates it.
 * v1 import currently rejects ZIP64 explicitly; never truncates its offsets or sizes. */
internal object BackupZipImporter {
    private val audioPath = Regex("recordings/recording-[A-Za-z0-9_-]{1,128}\\.(aac|mp3|m4a)")
    fun extract(file: File, output: File, cancelled: () -> Boolean,
                report: (BackupExportProgress) -> Unit): List<BackupImportEntry> {
        val names = inspect(file)
        check(output.mkdir()) { "import-staging-already-exists" }
        val result = mutableListOf<BackupImportEntry>()
        ZipFile(file).use { zip ->
            val entries = zip.entries().asSequence().toList()
            require(entries.size == names.size && entries.map { it.name } == names)
            val total = entries.sumOf { it.size }
            if (output.usableSpace < total + 65536) throw IOException("insufficient-import-space")
            var processed = 0L
            for ((index, item) in entries.withIndex()) {
                val hash = MessageDigest.getInstance("SHA-256")
                val crc = CRC32()
                val target = File(output, item.name.substringAfterLast('/'))
                zip.getInputStream(item).use { input ->
                    target.outputStream().use { sink ->
                        val count = BackupStreamCopy.copy(input, object : java.io.OutputStream() {
                            override fun write(b: Int) { error("chunked writes required") }
                            override fun write(b: ByteArray, off: Int, len: Int) {
                                hash.update(b, off, len); crc.update(b, off, len); sink.write(b, off, len)
                            }
                        }, cancelled, { bytes -> report(BackupExportProgress("checking", processed + bytes, total, index)) }, item.size)
                        require(count == item.size && crc.value == item.crc) { "archive-size-or-crc-mismatch" }
                        sink.fd.sync()
                    }
                }
                processed += item.size
                result += BackupImportEntry(item.name, item.size, hash.digest().joinToString("") { "%02x".format(it) })
            }
            report(BackupExportProgress("checking", processed, total, entries.size))
        }
        return result
    }

    fun inspect(file: File): List<String> = RandomAccessFile(file, "r").use { input ->
        fun u16(): Int = input.readUnsignedByte() or (input.readUnsignedByte() shl 8)
        fun u32(): Long = u16().toLong() or (u16().toLong() shl 16)
        val length = input.length()
        require(length in 22 until 0xffffffffL) { "zip64-or-invalid-archive-unsupported" }
        var end = length - 22
        val lower = maxOf(0, end - 65535)
        var found = false
        while (end >= lower) {
            input.seek(end)
            if (u32() == 0x06054b50L) {
                input.seek(end + 20)
                if (end + 22 + u16() == length) { found = true; break }
            }
            end--
        }
        require(found) { "zip-end-missing" }
        input.seek(end + 4)
        require(u16() == 0 && u16() == 0) { "multi-disk-unsupported" }
        val diskCount = u16(); val count = u16(); val size = u32(); val start = u32()
        require(count != 65535 && size != 0xffffffffL && start != 0xffffffffL) { "zip64-unsupported" }
        require(count == diskCount && count in 2..10002 && size <= 4 * 1024 * 1024 && start + size == end) { "zip-directory-limit-or-invalid" }
        val names = mutableListOf<String>()
        var audioBytes = 0L
        var cursor = start
        for (index in 0 until count) {
            require(cursor + 46 <= end)
            input.seek(cursor)
            require(u32() == 0x02014b50L)
            val madeBy = u16(); u16(); val flags = u16(); val method = u16()
            input.skipBytes(8)
            val compressed = u32(); val unpacked = u32()
            val nameLength = u16(); val extraLength = u16(); val commentLength = u16()
            val disk = u16(); u16(); val attributes = u32(); val local = u32()
            require(flags and 1 == 0 && flags and 64 == 0) { "encrypted-archive" }
            require(method == 0 && compressed == unpacked && disk == 0 && local < start && unpacked != 0xffffffffL) { "zip64-or-entry-unsupported" }
            require(nameLength in 1..180 && cursor + 46 + nameLength + extraLength + commentLength <= end)
            val bytes = ByteArray(nameLength); input.readFully(bytes)
            require(bytes.all { it.toInt() in 32..126 }) { "invalid-entry-name" }
            val name = bytes.toString(Charsets.US_ASCII)
            val extraEnd = input.filePointer + extraLength
            while (input.filePointer < extraEnd) {
                require(extraEnd - input.filePointer >= 4)
                val tag = u16(); val extraSize = u16()
                require(tag != 1) { "zip64-unsupported" }
                require(input.filePointer + extraSize <= extraEnd)
                input.skipBytes(extraSize)
            }
            val json = name == "manifest.json" || name == "metadata.json"
            require(json || audioPath.matches(name)) { "invalid-entry-path" }
            require(!names.contains(name)) { "duplicate-entry" }
            val mode = ((attributes ushr 16) and 0xf000).toInt()
            require((madeBy shr 8 != 3 || mode == 0 || mode == 0x8000) && attributes and 16 == 0L) { "non-regular-entry" }
            if (json) require(unpacked <= BackupZipExporter.MAX_JSON_BYTES)
            else { audioBytes += unpacked; require(audioBytes <= BackupZipExporter.MAX_AUDIO_BYTES) }
            // Check the local header as well; reject disagreements and overlapping directory data.
            input.seek(local); require(u32() == 0x04034b50L); u16()
            require(u16() == flags && u16() == method)
            input.skipBytes(16)
            val localName = u16(); val localExtra = u16()
            require(localName == nameLength && local + 30 + localName + localExtra + compressed <= start)
            val actualName = ByteArray(localName); input.readFully(actualName)
            require(actualName.contentEquals(bytes))
            names += name
            cursor += 46 + nameLength + extraLength + commentLength
        }
        require(cursor == end && names.containsAll(listOf("manifest.json", "metadata.json")))
        names
    }

    /** The destination directory belongs exclusively to this import's durable journal. */
    fun place(sources: List<Pair<File, File>>, cancelled: () -> Boolean, report: (BackupExportProgress) -> Unit) {
        val total = sources.sumOf { it.first.length() }
        if (sources.isNotEmpty() && sources.first().second.parentFile!!.usableSpace < total + 65536) throw IOException("insufficient-import-space")
        var done = 0L
        for ((index, pair) in sources.withIndex()) {
            if (cancelled()) throw CancellationException()
            val (source, target) = pair
            check(target.createNewFile()) { "import-target-occupied" }
            source.inputStream().use { input -> target.outputStream().use { output ->
                val expected = source.length()
                val copied = BackupStreamCopy.copy(input, output, cancelled, { report(BackupExportProgress("importing", done + it, total, index)) }, expected)
                require(copied == expected) { "import-source-changed" }
                output.fd.sync()
            } }
            done += source.length()
            report(BackupExportProgress("importing", done, total, index + 1))
        }
    }
}
