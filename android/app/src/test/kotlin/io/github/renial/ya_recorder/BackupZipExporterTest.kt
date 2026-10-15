package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

class BackupZipExporterTest {
    @get:Rule val temporary = TemporaryFolder()
    private val timestamp = "2026-10-15T06:30:00.000Z"
    private fun sources() = listOf("aac", "mp3", "m4a").map { format ->
        val file = temporary.newFile("sample.$format").apply { writeBytes(byteArrayOf(1, 2, 3, 4, 5)) }
        BackupExportSource("recordings/recording-sample-$format.$format", file, file.length())
    }
    private fun metadata(sources: List<BackupExportSource>): ByteArray {
        val recordings = sources.joinToString(",") {
            val format = it.path.substringAfterLast('.')
            val id = it.path.substringAfter("recording-").substringBeforeLast('.')
            """{"id":"$id","title":"录音 $format","created_at":"$timestamp","duration_ms":1500,"format":"$format","path":"${it.path}","file_size_bytes":${it.size},"folder_id":"folder-1720000000000000","was_interrupted":false}"""
        }
        return """{"folders":[{"id":"folder-1720000000000000","name":"旧文件夹","created_at":"$timestamp","sort_order":0},{"id":"folder-11111111-1111-4111-8111-111111111111","name":"Empty folder","created_at":"$timestamp","sort_order":1}],"recordings":[$recordings]}""".toByteArray(Charsets.UTF_8)
    }
    private fun create(file: File, sources: List<BackupExportSource>, report: (BackupExportProgress) -> Unit = {}): Long =
        BackupZipExporter.create(file, sources, metadata(sources), timestamp, 2, { false }, report)

    @Test fun roundTripsAllFormatsWithStoredEntriesAndStageProgress() {
        val sources = sources()
        val destination = File(temporary.root, "mixed.zip")
        val progress = mutableListOf<BackupExportProgress>()
        assertEquals(destination.length(), 0L)
        val size = create(destination, sources) { progress.add(it) }
        assertEquals(destination.length(), size)
        assertEquals(listOf("preparing", "packing", "verifying"), progress.map { it.stage }.distinct())
        for (stage in progress.groupBy { it.stage }.values) {
            assertTrue(stage.zipWithNext().all { (a, b) -> b.bytes >= a.bytes })
            assertEquals(stage.last().total, stage.last().bytes)
        }
        ZipFile(destination).use { zip ->
            assertEquals(5, zip.size())
            assertTrue(zip.entries().asSequence().all { it.method == ZipEntry.STORED && !it.isDirectory })
            val manifest = zip.getInputStream(zip.getEntry("manifest.json")).use { it.readBytes().toString(Charsets.UTF_8) }
            assertFalse(manifest.contains(temporary.root.path))
            assertTrue(manifest.contains("\"recording_count\":3"))
            for (source in sources) {
                val content = zip.getInputStream(zip.getEntry(source.path)).use { it.readBytes() }
                assertArrayEquals(source.file.readBytes(), content)
                val hash = MessageDigest.getInstance("SHA-256").digest(content).joinToString("") { "%02x".format(it) }
                assertTrue(manifest.contains(hash))
                assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5), source.file.readBytes())
            }
        }
        // Independent Dart contract verifier consumes these generated artifacts.
        fixtureDirectory().apply { mkdirs() }.resolve("mixed.zip").writeBytes(destination.readBytes())
    }

    @Test fun emptyLibraryKeepsEmptyFoldersAndBothJsonFiles() {
        val destination = File(temporary.root, "empty.zip")
        create(destination, emptyList())
        ZipFile(destination).use { zip ->
            assertEquals(2, zip.size())
            val manifest = zip.getInputStream(zip.getEntry("manifest.json")).use { it.readBytes().toString(Charsets.UTF_8) }
            assertTrue(manifest.contains("\"recording_count\":0"))
            assertTrue(manifest.contains("\"folder_count\":2"))
        }
        fixtureDirectory().apply { mkdirs() }.resolve("empty.zip").writeBytes(destination.readBytes())
    }

    @Test fun missingWrongSizeAndWrongExtensionFailBeforeCreatingZip() {
        val good = sources().first()
        val bad = listOf(good.copy(file = File(temporary.root, "missing.aac")), good.copy(size = 6), good.copy(path = "recordings/recording-sample-aac.mp3"))
        for (source in bad) {
            val output = File(temporary.root, "bad.zip")
            assertThrows(IOException::class.java) { create(output, listOf(source)) }
            assertFalse(output.exists())
            assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5), good.file.readBytes())
        }
    }

    @Test fun sameSizeMutationBetweenHashAndPackagingIsRejected() {
        val source = sources().first()
        val output = File(temporary.root, "changed.zip")
        assertThrows(IOException::class.java) {
            create(output, listOf(source)) { if (it.stage == "packing" && it.bytes == 0L) source.file.writeBytes(byteArrayOf(5, 4, 3, 2, 1)) }
        }
        assertFalse(output.exists())
        assertTrue(source.file.exists())
    }

    @Test fun cancellationDuringEachStageNeverLeavesSuccessfulArchive() {
        val sources = sources()
        for (stage in listOf("preparing", "packing", "verifying")) {
            var cancelled = false
            val output = File(temporary.root, "cancel-$stage.zip")
            assertThrows(CancellationException::class.java) {
                BackupZipExporter.create(output, sources, metadata(sources), timestamp, 2, { cancelled }, { if (it.stage == stage) cancelled = true })
            }
            assertFalse(output.exists())
            assertTrue(sources.all { it.file.exists() })
        }
    }

    @Test fun corruptContentFailsReadbackEvenWhenDirectoryCrcIsUnchanged() {
        val source = sources().first()
        val output = File(temporary.root, "corrupt.zip")
        create(output, listOf(source))
        val expected = ZipFile(output).use { zip -> zip.entries().asSequence().map { item ->
            val bytes = zip.getInputStream(item).use { it.readBytes() }
            BackupExportDigest(item.name, item.size, MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }, item.crc)
        }.toList() }
        val bytes = output.readBytes()
        val offset = (0..bytes.size - 5).first { bytes.sliceArray(it until it + 5).contentEquals(byteArrayOf(1, 2, 3, 4, 5)) }
        RandomAccessFile(output, "rw").use { it.seek(offset.toLong()); it.write(9) }
        assertThrows(IOException::class.java) { BackupZipExporter.verify(output, expected, { false }, {}) }
    }

    @Test fun preflightsTemporarySpaceAndUsesLongSizeEstimates() {
        val source = sources().first()
        val output = File(temporary.root, "no-space.zip")
        assertThrows(IOException::class.java) {
            BackupZipExporter.create(output, listOf(source), metadata(listOf(source)), timestamp, 2, { false }, {}, { 0L })
        }
        assertFalse(output.exists())
        val fiveGiB = 5L * 1024 * 1024 * 1024
        assertTrue(BackupZipExporter.estimateArchiveBytes(fiveGiB, 1024, 1024, 1) > fiveGiB)
    }

    @Test fun rejectsUnsafePathsDuplicateNamesAndResourceOverflow() {
        val source = sources().first()
        for (bad in listOf(listOf(source.copy(path = "../escape.aac")), listOf(source, source), listOf(source.copy(size = BackupZipExporter.MAX_AUDIO_BYTES + 1)))) {
            assertThrows(IllegalArgumentException::class.java) { create(File(temporary.root, "bad.zip"), bad) }
        }
    }

    @Test fun manyShortSourcesRemainSeparateAndOriginalsAreUntouched() {
        val sources = (0 until 512).map { index ->
            val file = temporary.newFile("$index.aac").apply { writeBytes(byteArrayOf(index.toByte())) }
            BackupExportSource("recordings/recording-$index.aac", file, 1)
        }
        val output = File(temporary.root, "many.zip")
        create(output, sources)
        ZipFile(output).use { assertEquals(514, it.size()) }
        assertTrue(sources.all { it.file.length() == 1L })
    }

    private fun fixtureDirectory(): File {
        val root = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }.first { File(it, "pubspec.yaml").isFile }
        return File(root, "build/bkp04-native-samples")
    }
}
