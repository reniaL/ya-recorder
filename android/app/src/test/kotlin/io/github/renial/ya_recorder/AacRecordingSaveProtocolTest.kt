package io.github.renial.ya_recorder

import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AacRecordingSaveProtocolTest {
    @get:Rule val temporary = TemporaryFolder()
    private val root get() = temporary.root
    private var failReadyWrite = false
    private val io = object : DraftIo {
        override fun read(file: File) = file.readBytes()
        override fun write(file: File, data: ByteArray) {
            check(!failReadyWrite || !String(data).contains("phase=READY"))
            file.writeBytes(data)
        }
        override fun delete(file: File) { check(!file.exists() || file.delete()) }
    }
    private fun drafts() = RecordingDraftStore(File(root, "recovery"), io)
    private fun protocol(move: (File, File) -> Boolean = { from, to -> from.renameTo(to) }) =
        RecordingSaveProtocol(root, drafts(), validate = { file, format ->
            assertEquals(RecordingFormat.AAC, format)
            RecordingMediaValidation.validateContainer(file, format)
            3000L // Simulated PCM duration; payload decode is a device check.
        }, repairMp3 = { _, _ -> error("AAC must never use MP3 prefix repair") }, move = move)

    private fun begin(p: RecordingSaveProtocol): File {
        p.begin("aac-one", 1234, RecordingFormat.AAC)
        return p.temporary("aac-one", RecordingFormat.AAC).apply { writeBytes(adtsFrame(10)) }
    }

    @Test fun normalStopCommitsDecodedDurationAndWaitsForIndexAcknowledgement() {
        val p = protocol()
        val source = begin(p)
        val bytes = source.readBytes()
        val ready = p.finish("aac-one", null)
        assertEquals("recording-aac-one.aac", ready.file.name)
        assertEquals(3000L, ready.draft.durationMs)
        assertEquals("aac", ready.toMap()["format"])
        assertFalse(ready.draft.wasInterrupted)
        assertArrayEquals(bytes, ready.file.readBytes())
        assertFalse(source.exists())
        assertEquals(DraftPhase.READY, drafts().read("aac-one").phase)
        assertTrue(p.recover().recordings.isEmpty()) // Active lease still protects it.
        p.releaseLease("aac-one")
        assertEquals(ready, p.recover().recordings.single())
        p.acknowledge("aac-one")
        assertTrue(drafts().ids().isEmpty())
        assertTrue(ready.file.isFile)
    }

    @Test fun completeInterruptedAacIsRecoveredWithoutRepairAndReplaysIdempotently() {
        val p = protocol()
        val source = begin(p)
        val bytes = source.readBytes()
        val reopened = protocol()
        val ready = reopened.recover().recordings.single()
        assertTrue(ready.draft.wasInterrupted)
        assertEquals(RecordingFormat.AAC, ready.draft.format)
        assertArrayEquals(bytes, ready.file.readBytes())
        assertEquals(ready, reopened.recover().recordings.single())
        reopened.acknowledge("aac-one")
        reopened.acknowledge("aac-one")
        assertTrue(reopened.recover().recordings.isEmpty())
        assertTrue(ready.file.isFile)
    }

    @Test fun truncatedAacStopAndRecoveryRetainOriginalBytesAndNeverReturnAReadyFile() {
        val p = protocol()
        val source = begin(p)
        val bytes = adtsFrame(10) + adtsFrame(10).dropLast(1).toByteArray()
        source.writeBytes(bytes)
        assertThrows(IllegalStateException::class.java) { p.finish("aac-one", null) }
        assertEquals(DraftPhase.FINALIZING, drafts().read("aac-one").phase)
        p.releaseLease("aac-one")
        val batch = protocol().recover()
        assertTrue(batch.recordings.isEmpty())
        assertEquals(listOf("aac-one"), batch.unresolvedIds)
        assertArrayEquals(bytes, source.readBytes())
        assertFalse(p.completed("aac-one", RecordingFormat.AAC).exists())
    }

    @Test fun cancelledAacIsNeverRecoveredAsAnInterruptedRecording() {
        val p = protocol()
        val source = begin(p)
        p.markDiscarding("aac-one")
        assertTrue(p.recover().recordings.isEmpty())
        p.releaseLease("aac-one")
        assertTrue(protocol().recover().recordings.isEmpty())
        assertFalse(source.exists())
        assertTrue(drafts().ids().isEmpty())
    }

    @Test fun renameFailureAndLostReadyWriteReplayWithoutMarkingNormalStopInterrupted() {
        val p = protocol(move = { _, _ -> false })
        begin(p)
        assertThrows(IllegalStateException::class.java) { p.finish("aac-one", null) }
        assertEquals(DraftPhase.VALIDATED, drafts().read("aac-one").phase)
        failReadyWrite = true
        assertEquals(listOf("aac-one"), protocol().recover().unresolvedIds)
        assertTrue(p.completed("aac-one", RecordingFormat.AAC).isFile)
        failReadyWrite = false
        val ready = protocol().recover().recordings.single()
        assertFalse(ready.draft.wasInterrupted)
        assertEquals(DraftPhase.READY, drafts().read("aac-one").phase)
    }

    @Test fun changedReadyAudioCannotBeReplayedIntoTheIndex() {
        val p = protocol()
        begin(p)
        val ready = p.finish("aac-one", null)
        p.releaseLease("aac-one")
        ready.file.writeBytes(ready.file.readBytes().dropLast(1).toByteArray())
        assertEquals(listOf("aac-one"), protocol().recover().unresolvedIds)
        assertEquals(DraftPhase.READY, drafts().read("aac-one").phase)
        assertTrue(ready.file.exists())
    }
}
