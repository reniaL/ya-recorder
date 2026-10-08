package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class RecordingSaveProtocolTest {
    @get:Rule val temporary = TemporaryFolder()
    private val root get() = temporary.root
    private var failWritePhase: String? = null
    private var failDraftDeletion = false
    private val io = object : DraftIo {
        override fun read(file: File) = file.readBytes()
        override fun write(file: File, data: ByteArray) {
            check(failWritePhase == null || !String(data).contains("phase=$failWritePhase")) { "Draft storage failed" }
            file.writeBytes(data)
        }
        override fun delete(file: File) { check(!failDraftDeletion); check(!file.exists() || file.delete()) }
    }
    private fun store() = RecordingDraftStore(File(root, "recovery"), io)
    private fun protocol(
        validate: (File, RecordingFormat) -> Long = { file, _ -> check(file.length() > 0); 3000L },
        move: (File, File) -> Boolean = { a, b -> a.renameTo(b) },
        delete: (File) -> Boolean = { it.delete() },
    ) = RecordingSaveProtocol(root, store(), validate,
        repairMp3 = { source, target -> source.copyTo(target) }, move = move, deleteFile = delete)

    private fun audio(protocol: RecordingSaveProtocol, format: RecordingFormat = RecordingFormat.M4A) {
        protocol.begin("one", 1234, format)
        protocol.temporary("one", format).writeBytes(ByteArray(128) { 7 })
    }

    @Test fun draftPrecedesAudioAndSurvivesRestartWithExplicitFormat() {
        val p = protocol()
        p.begin("one", 1234, RecordingFormat.MP3)
        val draft = store().read("one")
        assertEquals(RecordingFormat.MP3, draft.format)
        assertEquals(1234L, draft.createdAtMs)
        assertEquals(DraftPhase.CAPTURING, draft.phase)
        assertFalse(p.temporary("one", draft.format).exists())
        assertEquals(listOf("one"), store().ids())
    }

    @Test fun fullCommitRetainsReadyDraftUntilIndexAcknowledgement() {
        val p = protocol(); audio(p)
        val ready = p.finish("one", null)
        assertEquals(DraftPhase.READY, store().read("one").phase)
        assertFalse(ready.draft.wasInterrupted)
        assertTrue(ready.file.isFile)
        assertFalse(p.temporary("one", RecordingFormat.M4A).exists())
        assertEquals(emptyList<ReadyRecording>(), p.recover().recordings) // still leased
        p.releaseLease("one")
        assertEquals(ready, p.recover().recordings.single())
        p.acknowledge("one"); p.acknowledge("one")
        assertTrue(store().ids().isEmpty())
        assertTrue(ready.file.isFile)
    }

    @Test fun activeAndTimedOutWritersAreNeverRecoveredOrDiscarded() {
        val p = protocol(); audio(p)
        assertTrue(p.recover().recordings.isEmpty())
        expectFailure { p.recoverOne("one") }
        p.markDiscarding("one")
        expectFailure { p.discard("one") }
        assertTrue(p.temporary("one", RecordingFormat.M4A).isFile)
    }

    @Test fun crashBeforeStopRecoversValidatedM4aAsInterrupted() {
        val p = protocol(); audio(p)
        val ready = protocol().recover().recordings.single()
        assertTrue(ready.draft.wasInterrupted)
        assertEquals(RecordingFormat.M4A, ready.draft.format)
        assertEquals(3000L, ready.draft.durationMs)
    }

    @Test fun mp3PartialRecoveryKeepsOriginalUntilAcknowledged() {
        val p = protocol(); audio(p, RecordingFormat.MP3)
        val original = p.temporary("one", RecordingFormat.MP3)
        val bytes = original.readBytes()
        val recovered = protocol().recover().recordings.single()
        assertTrue(recovered.draft.wasInterrupted)
        assertArrayEquals(bytes, original.readBytes())
        protocol().acknowledge("one")
        assertFalse(original.exists())
        assertTrue(recovered.file.exists())
    }

    @Test fun invalidOrUnsealedAudioRemainsOutsideIndexAndReadyResults() {
        val p = protocol(); audio(p)
        val reopened = protocol(validate = { _, _ -> error("not decodable") })
        val batch = reopened.recover()
        assertTrue(batch.recordings.isEmpty())
        assertEquals(listOf("one"), batch.unresolvedIds)
        assertEquals(DraftPhase.CAPTURING, store().read("one").phase)
        assertTrue(p.temporary("one", RecordingFormat.M4A).exists())
    }

    @Test fun sampleDurationMismatchCannotReportNormalCompleteSave() {
        val p = protocol(); audio(p, RecordingFormat.MP3)
        expectFailure { p.finish("one", 1000) }
        assertFalse(p.completed("one", RecordingFormat.MP3).exists())
        assertEquals(DraftPhase.FINALIZING, store().read("one").phase)
    }

    @Test fun renameFailureLeavesValidatedDraftAndAudioForReplay() {
        val p = protocol(move = { _, _ -> false }); audio(p)
        expectFailure { p.finish("one", null) }
        assertEquals(DraftPhase.VALIDATED, store().read("one").phase)
        val ready = protocol().recover().recordings.single()
        assertFalse(ready.draft.wasInterrupted)
    }

    @Test fun crashBetweenRenameAndReadyUpdateRepairsOnlyJournal() {
        val p = protocol(); audio(p)
        val source = p.temporary("one", RecordingFormat.M4A)
        store().write(store().read("one").copy(phase = DraftPhase.VALIDATED, durationMs = 3000, fileSizeBytes = 128))
        check(source.renameTo(p.completed("one", RecordingFormat.M4A)))
        val ready = protocol().recover().recordings.single()
        assertFalse(ready.draft.wasInterrupted)
        assertEquals(DraftPhase.READY, store().read("one").phase)
        assertEquals(ready, protocol().recover().recordings.single())
    }

    @Test fun cancellationTombstoneSurvivesFailureAndRestartNeverImportsIt() {
        val p = protocol(delete = { false }); audio(p)
        p.markDiscarding("one"); p.releaseLease("one")
        expectFailure { p.discard("one") }
        assertEquals(DraftPhase.DISCARDING, store().read("one").phase)
        assertTrue(protocol().recover().recordings.isEmpty())
        assertFalse(p.temporary("one", RecordingFormat.M4A).exists())
        assertTrue(store().ids().isEmpty())
    }

    @Test fun cancellationAfterAudioDeletionStillClearsTombstoneOnReplay() {
        val p = protocol(); audio(p)
        p.markDiscarding("one")
        p.temporary("one", RecordingFormat.M4A).delete()
        assertTrue(protocol().recover().recordings.isEmpty())
        assertTrue(store().ids().isEmpty())
    }

    @Test fun conflictsNeverOverwriteAnExistingFinalFile() {
        val p = protocol(); audio(p)
        val final = p.completed("one", RecordingFormat.M4A)
        final.writeText("untouchable")
        expectFailure { p.finish("one", null) }
        assertEquals("untouchable", final.readText())
        expectFailure { protocol().recoverOne("one") }
        assertEquals("untouchable", final.readText())
    }

    @Test fun missingReadyFileCannotBeReturnedForIndexCommit() {
        val p = protocol(); audio(p)
        val ready = p.finish("one", null)
        ready.file.delete()
        assertEquals(listOf("one"), protocol().recover().unresolvedIds)
        assertEquals(DraftPhase.READY, store().read("one").phase)
    }

    @Test fun invalidDraftDoesNotPreventAnotherRecordingRecovery() {
        val p = protocol(); audio(p)
        File(root, "recovery/bad.draft").writeText("version=999")
        val batch = protocol().recover()
        assertEquals("one", batch.recordings.single().draft.id)
        assertEquals(listOf("bad"), batch.unresolvedIds)
    }

    @Test fun identitiesAndUnknownFormatsCannotEscapePrivateDirectories() {
        expectFailure { protocol().begin("../outside", 1, RecordingFormat.M4A) }
        expectFailure { protocol().begin("one", -1, RecordingFormat.M4A) }
        val p = protocol(); audio(p)
        val draftFile = File(root, "recovery/one.draft")
        draftFile.writeText(draftFile.readText().replace("format=m4a", "format=wav"))
        assertEquals(listOf("one"), protocol().recover().unresolvedIds)
    }

    @Test fun failedReadyJournalUpdateAfterRenameIsReplayable() {
        val p = protocol(); audio(p)
        failWritePhase = "READY"
        expectFailure { p.finish("one", null) }
        assertEquals(DraftPhase.VALIDATED, store().read("one").phase)
        assertTrue(p.completed("one", RecordingFormat.M4A).exists())
        failWritePhase = null
        assertFalse(protocol().recover().recordings.single().draft.wasInterrupted)
    }

    @Test fun failedAcknowledgementCleanupRetainsIdempotentReplay() {
        val p = protocol(); audio(p); p.finish("one", null); p.releaseLease("one")
        failDraftDeletion = true
        expectFailure { p.acknowledge("one") }
        assertEquals(DraftPhase.READY, store().read("one").phase)
        assertEquals("one", protocol().recover().recordings.single().draft.id)
        failDraftDeletion = false
        p.acknowledge("one")
        assertTrue(store().ids().isEmpty())
        assertTrue(p.completed("one", RecordingFormat.M4A).exists())
    }

    @Test fun untrackedLegacyResidualsAreReportedAndNeverImportedOrDeleted() {
        val p = protocol()
        File(root, "recovery").mkdirs()
        val orphan = p.temporary("legacy", RecordingFormat.MP3).apply { writeText("unclassified") }
        val batch = p.recover()
        assertTrue(batch.recordings.isEmpty())
        assertEquals(listOf(orphan.name), batch.unresolvedIds)
        assertEquals("unclassified", orphan.readText())
    }

    private fun expectFailure(action: () -> Unit) {
        try { action(); fail("Expected operation failure") } catch (_: Exception) { }
    }
}
