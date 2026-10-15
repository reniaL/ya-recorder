package io.github.renial.ya_recorder

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

internal data class BackupExportSource(val path: String, val file: File, val size: Long)
internal data class BackupExportProgress(val stage: String, val bytes: Long, val total: Long, val recordings: Int)
internal data class BackupExportDigest(val path: String, val size: Long, val sha256: String, val crc: Long)

/** Pure JVM worker, also used on Android. No database, UI or whole-audio buffers. */
internal object BackupZipExporter {
    const val MAX_AUDIO_BYTES = 16L * 1024 * 1024 * 1024
    const val MAX_JSON_BYTES = 16 * 1024 * 1024
    private val pathPattern = Regex("recordings/recording-[A-Za-z0-9_-]{1,128}\\.(aac|mp3|m4a)")

    fun create(
        destination: File,
        sources: List<BackupExportSource>,
        metadata: ByteArray,
        createdAt: String,
        folderCount: Int,
        cancelled: () -> Boolean,
        report: (BackupExportProgress) -> Unit,
        availableBytes: () -> Long = { destination.parentFile!!.usableSpace },
    ): Long {
        checkCancelled(cancelled)
        require(sources.size <= 10000 && folderCount in 0..10000)
        require(metadata.size <= MAX_JSON_BYTES)
        require(Regex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}(\\d{3})?Z").matches(createdAt))
        require(sources.map { it.path }.toSet().size == sources.size)
        var total = 0L
        for (source in sources) {
            require(pathPattern.matches(source.path) && source.size > 0)
            total = Math.addExact(total, source.size)
            require(total <= MAX_AUDIO_BYTES)
            if (!source.file.isFile || source.file.length() != source.size ||
                !source.file.name.endsWith(".${source.path.substringAfterLast('.')}", ignoreCase = true)) {
                throw IOException("source-missing-or-inconsistent: ${source.path}")
            }
        }
        // Sources already occupy disk. Extra disk is one complete ZIP; a local
        // provider may require a second copy, whose capacity is not queryable here.
        val initialEstimate = estimateArchiveBytes(total, metadata.size.toLong(), (sources.size + 1L) * 512 + 512, sources.size)
        if (availableBytes() < initialEstimate) throw IOException("insufficient-temporary-space")
        var processed = 0L
        report(BackupExportProgress("preparing", 0, total, 0))
        val digests = sources.mapIndexed { index, source ->
            source.file.inputStream().use { input ->
                scan(source.path, source.size, input, null, cancelled) { bytes ->
                    report(BackupExportProgress("preparing", processed + bytes, total, index))
                }
            }.also { processed += it.size }
        }
        val metaDigest = digestBytes("metadata.json", metadata)
        // This envelope contains only validated ASCII paths/timestamps and
        // computed hex/numeric fields. User text is already jsonEncode'd in metadata.
        val manifest = manifest(createdAt, folderCount, listOf(metaDigest) + digests)
        require(manifest.size <= MAX_JSON_BYTES)
        val manifestDigest = digestBytes("manifest.json", manifest)
        val expected = listOf(manifestDigest, metaDigest) + digests
        val required = estimateArchiveBytes(total, metadata.size.toLong(), manifest.size.toLong(), sources.size)
        if (availableBytes() < required) throw IOException("insufficient-temporary-space")
        val packingTotal = expected.sumOf { it.size }
        processed = 0
        report(BackupExportProgress("packing", 0, packingTotal, 0))
        try {
            // ZipOutputStream.finish can throw on a changed source CRC. Own the
            // underlying file separately so Windows/Android handles still close.
            destination.outputStream().buffered(64 * 1024).use { output ->
            ZipOutputStream(output).use { zip ->
                fun jsonEntry(bytes: ByteArray, digest: BackupExportDigest) {
                    checkCancelled(cancelled)
                    zip.putNextEntry(entry(digest))
                    zip.write(bytes)
                    zip.closeEntry()
                    processed += bytes.size
                    report(BackupExportProgress("packing", processed, packingTotal, 0))
                }
                jsonEntry(manifest, manifestDigest)
                jsonEntry(metadata, metaDigest)
                for ((index, source) in sources.withIndex()) {
                    checkCancelled(cancelled)
                    val expectedDigest = digests[index]
                    zip.putNextEntry(entry(expectedDigest))
                    val actual = source.file.inputStream().use { input ->
                        scan(source.path, source.size, input, zip, cancelled) { bytes ->
                            report(BackupExportProgress("packing", processed + bytes, packingTotal, index))
                        }
                    }
                    if (actual != expectedDigest) throw IOException("source-changed: ${source.path}")
                    zip.closeEntry()
                    processed += source.size
                    report(BackupExportProgress("packing", processed, packingTotal, index + 1))
                }
            }
            }
            checkCancelled(cancelled)
            verify(destination, expected, cancelled, report)
            return destination.length()
        } catch (error: Exception) {
            destination.delete() // Runtime retains the task directory if cleanup needs retry.
            throw error
        }
    }

    fun estimateArchiveBytes(audio: Long, metadata: Long, manifest: Long, recordings: Int): Long {
        require(audio in 0..MAX_AUDIO_BYTES && metadata >= 0 && manifest >= 0 && recordings in 0..10000)
        // Two headers, longest UTF-8 name, ZIP64 extras/offsets and EOCD reserve.
        return Math.addExact(Math.addExact(audio, metadata + manifest), (recordings + 2L) * 512 + 65536)
    }

    fun verify(file: File, expected: List<BackupExportDigest>, cancelled: () -> Boolean, report: (BackupExportProgress) -> Unit) {
        val total = expected.sumOf { it.size }
        var processed = 0L
        report(BackupExportProgress("verifying", 0, total, 0))
        ZipFile(file).use { zip ->
            val entries = zip.entries().asSequence().toList()
            if (entries.size != expected.size || entries.map { it.name }.toSet() != expected.map { it.path }.toSet()) {
                throw IOException("archive-inventory-mismatch")
            }
            for ((index, digest) in expected.withIndex()) {
                checkCancelled(cancelled)
                val item = zip.getEntry(digest.path)
                if (item.isDirectory || item.method != ZipEntry.STORED || item.size != digest.size || item.crc != digest.crc) {
                    throw IOException("archive-entry-mismatch: ${digest.path}")
                }
                val actual = zip.getInputStream(item).use { input ->
                    scan(digest.path, digest.size, input, null, cancelled) { bytes ->
                        report(BackupExportProgress("verifying", processed + bytes, total, maxOf(0, index - 2)))
                    }
                }
                if (actual != digest) throw IOException("archive-checksum-mismatch: ${digest.path}")
                processed += digest.size
            }
        }
        report(BackupExportProgress("verifying", processed, total, maxOf(0, expected.size - 2)))
    }

    private fun scan(path: String, size: Long, input: InputStream, output: OutputStream?, cancelled: () -> Boolean, progress: (Long) -> Unit): BackupExportDigest {
        val hash = MessageDigest.getInstance("SHA-256")
        val crc = CRC32()
        val buffer = ByteArray(64 * 1024)
        var bytes = 0L
        while (true) {
            checkCancelled(cancelled)
            val count = input.read(buffer)
            checkCancelled(cancelled)
            if (count < 0) break
            if (count == 0) continue
            if (count > size - bytes) throw IOException("source-size-mismatch: $path")
            hash.update(buffer, 0, count)
            crc.update(buffer, 0, count)
            output?.write(buffer, 0, count)
            bytes += count
            progress(bytes)
        }
        if (bytes != size) throw IOException("source-size-mismatch: $path")
        return BackupExportDigest(path, bytes, hash.digest().joinToString("") { "%02x".format(it) }, crc.value)
    }

    private fun digestBytes(path: String, bytes: ByteArray) = scan(path, bytes.size.toLong(), bytes.inputStream(), null, { false }, {})
    private fun entry(digest: BackupExportDigest) = ZipEntry(digest.path).apply {
        method = ZipEntry.STORED; size = digest.size; compressedSize = digest.size; crc = digest.crc
    }
    private fun checkCancelled(cancelled: () -> Boolean) { if (cancelled()) throw CancellationException("Backup cancelled") }
    private fun manifest(createdAt: String, folders: Int, files: List<BackupExportDigest>): ByteArray {
        val inventory = files.joinToString(",") { "{\"path\":\"${it.path}\",\"size_bytes\":${it.size},\"sha256\":\"${it.sha256}\"}" }
        return ("{\"backup_type\":\"io.github.renial.ya_recorder.backup\",\"format_version\":1," +
            "\"created_at\":\"$createdAt\",\"recording_count\":${files.size - 1},\"folder_count\":$folders,\"files\":[$inventory]}").toByteArray(Charsets.UTF_8)
    }
}
