package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.CancellationException
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class BackupZipImporterTest {
    @get:Rule val temporary = TemporaryFolder()
    private fun archive(name: String = "good.zip", extra: List<String> = listOf("recordings/recording-id.aac")): File {
        val file = File(temporary.root, name)
        ZipOutputStream(file.outputStream()).use { zip ->
            for (path in listOf("manifest.json", "metadata.json") + extra) {
                val bytes = byteArrayOf(1, 2, 3)
                val entry = ZipEntry(path).apply { method = ZipEntry.STORED; size = 3; compressedSize = 3; crc = CRC32().apply { update(bytes) }.value }
                zip.putNextEntry(entry); zip.write(bytes); zip.closeEntry()
            }
        }
        return file
    }
    private fun extract(file: File, cancel: () -> Boolean = { false }, report: (BackupExportProgress) -> Unit = {}) =
        BackupZipImporter.extract(file, File(temporary.root, "extracted"), cancel, report)
    private fun central(file: File): Int = file.readBytes().let { bytes ->
        (0..bytes.size - 4).first { bytes[it] == 0x50.toByte() && bytes[it + 1] == 0x4b.toByte() && bytes[it + 2] == 1.toByte() && bytes[it + 3] == 2.toByte() }
    }
    private fun patch(file: File, offset: Long, vararg bytes: Int) { RandomAccessFile(file, "rw").use { f -> f.seek(offset); bytes.forEach { f.write(it) } } }

    @Test fun extractsThreeFormatsWithHashesAndRealByteProgress() {
        val file = archive(extra = listOf("aac", "mp3", "m4a").map { "recordings/recording-$it.$it" })
        val progress = mutableListOf<BackupExportProgress>()
        val entries = extract(file, report = { progress += it })
        assertEquals(5, entries.size)
        assertTrue(entries.all { it.sha256 == "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81" })
        assertEquals(15L, progress.last().bytes)
        assertEquals(progress.last().total, progress.last().bytes)
        for (entry in entries) assertArrayEquals(byteArrayOf(1, 2, 3), File(temporary.root, "extracted/${entry.path.substringAfterLast('/')}").readBytes())
    }

    @Test fun rejectsTraversalAndNonStoredEntries() {
        assertThrows(IllegalArgumentException::class.java) { BackupZipImporter.inspect(archive(extra = listOf("../outside"))) }
        val file = archive("compressed.zip")
        patch(file, central(file).toLong() + 10, 8, 0)
        assertThrows(IllegalArgumentException::class.java) { BackupZipImporter.inspect(file) }
        assertFalse(File(temporary.root, "outside").exists())
    }

    @Test fun rejectsEncryptionAndUnixSymlinksBeforeExtraction() {
        val encrypted = archive()
        patch(encrypted, central(encrypted).toLong() + 8, 1, 0)
        assertThrows(IllegalArgumentException::class.java) { BackupZipImporter.inspect(encrypted) }
        val link = archive("link.zip")
        val offset = central(link).toLong()
        patch(link, offset + 5, 3) // Unix creator
        patch(link, offset + 38, 0, 0, 0, 0xa0)
        assertThrows(IllegalArgumentException::class.java) { BackupZipImporter.inspect(link) }
    }

    @Test fun rejectsRawDuplicateNamesAndLocalHeaderDisagreement() {
        val file = archive(extra = listOf("recordings/recording-aa.aac", "recordings/recording-bb.aac"))
        val bytes = file.readBytes()
        val from = "recording-bb".toByteArray(); val to = "recording-aa".toByteArray()
        for (i in 0..bytes.size - from.size) if (bytes.copyOfRange(i, i + from.size).contentEquals(from)) to.copyInto(bytes, i)
        file.writeBytes(bytes)
        assertThrows(IllegalArgumentException::class.java) { BackupZipImporter.inspect(file) }
        val mismatch = archive("mismatch.zip")
        patch(mismatch, 30, 'x'.code)
        assertThrows(IllegalArgumentException::class.java) { BackupZipImporter.inspect(mismatch) }
    }

    @Test fun rejectsDirectoryCountAllocationBombAndZip64Sentinels() {
        val file = archive()
        patch(file, file.length() - 12, 0xff, 0xff)
        assertThrows(IllegalArgumentException::class.java) { BackupZipImporter.inspect(file) }
        val huge = archive("huge.zip")
        patch(huge, huge.length() - 10, 0xff, 0xff, 0xff, 0xff)
        assertThrows(IllegalArgumentException::class.java) { BackupZipImporter.inspect(huge) }
    }

    @Test fun corruptContentFailsCrcAndCancellationStopsAtChunkBoundary() {
        val file = archive()
        patch(file, 30L + "manifest.json".length, 9)
        assertThrows(IllegalArgumentException::class.java) { extract(file) }
        File(temporary.root, "extracted").deleteRecursively()
        assertThrows(CancellationException::class.java) { extract(archive("cancel.zip"), { true }) }
    }

    @Test fun refusesOccupiedTargetsAndStreamsWithoutChangingSources() {
        val source = temporary.newFile("audio.aac").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        val target = temporary.newFile("target.aac").apply { writeBytes(byteArrayOf(9)) }
        assertThrows(IllegalStateException::class.java) { BackupZipImporter.place(listOf(source to target), { false }, {}) }
        assertArrayEquals(byteArrayOf(9), target.readBytes())
        target.delete()
        BackupZipImporter.place(listOf(source to target), { false }, {})
        assertArrayEquals(source.readBytes(), target.readBytes())
    }

    @Test fun faultsAfterEveryPlacedFileLeaveOwnedPartialFilesForJournalRecovery() {
        for (failureIndex in 0..2) {
            val sources = (0..2).map { i -> temporary.newFile("source-$failureIndex-$i").apply { writeBytes(byteArrayOf(1, 2, 3)) } }
            val targets = (0..2).map { i -> File(temporary.root, "target-$failureIndex-$i") }
            assertThrows(java.io.IOException::class.java) {
                BackupZipImporter.place(sources.zip(targets), { false }) {
                    if (it.recordings == failureIndex + 1) throw java.io.IOException("injected-file-boundary")
                }
            }
            assertTrue(targets.take(failureIndex + 1).all { it.exists() })
            assertTrue(targets.drop(failureIndex + 1).none { it.exists() })
            assertTrue(sources.all { it.readBytes().contentEquals(byteArrayOf(1, 2, 3)) })
        }
    }

    @Test fun nativeExporterOutputPassesUntrustedImportAdapter() {
        val sources = listOf("aac", "mp3", "m4a").map {
            BackupExportSource("recordings/recording-$it.$it", temporary.newFile("$it.audio").apply { writeBytes(byteArrayOf(1)) }, 1)
        }.map { s -> s.copy(file = File(temporary.root, s.path.substringAfterLast('/')).apply { writeBytes(byteArrayOf(1)) }) }
        val zip = File(temporary.root, "roundtrip.zip")
        BackupZipExporter.create(zip, sources, "{\"folders\":[],\"recordings\":[]}".toByteArray(), "2026-10-15T06:30:00.000Z", 0, { false }, {})
        val result = extract(zip)
        assertEquals(5, result.size)
        assertTrue(result.filter { it.path.startsWith("recordings/") }.all { it.size == 1L })
    }
}
