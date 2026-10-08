package io.github.renial.ya_recorder

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Properties

internal enum class DraftPhase { CAPTURING, FINALIZING, VALIDATED, READY, DISCARDING }

internal data class RecordingDraft(
    val id: String,
    val createdAtMs: Long,
    val format: RecordingFormat,
    val phase: DraftPhase = DraftPhase.CAPTURING,
    val durationMs: Long = 0,
    val fileSizeBytes: Long = 0,
    val wasInterrupted: Boolean = false,
) {
    init {
        format.completedFileName(id)
        require(createdAtMs >= 0 && durationMs >= 0 && fileSizeBytes >= 0)
        if (phase == DraftPhase.READY || phase == DraftPhase.VALIDATED) {
            require(durationMs > 0 && fileSizeBytes > 0)
        }
    }
}

/** Atomic journal I/O is supplied by Android; JVM tests inject filesystem I/O. */
internal interface DraftIo {
    fun read(file: File): ByteArray
    fun write(file: File, data: ByteArray)
    fun delete(file: File)
}

internal class RecordingDraftStore(private val directory: File, private val io: DraftIo) {
    fun ids(): List<String> {
        check(directory.mkdirs() || directory.isDirectory)
        return checkNotNull(directory.listFiles()).mapNotNull {
            val name = it.name.removeSuffix(".bak").removeSuffix(".new")
            if (name.endsWith(".draft")) name.removeSuffix(".draft") else null
        }.distinct().sorted()
    }

    fun read(id: String): RecordingDraft {
        val properties = Properties().apply { io.read(file(id)).inputStream().use { load(it) } }
        check(properties.getProperty("version") == "1") { "Unsupported recording draft version" }
        check(properties.getProperty("id") == id) { "Recording draft identity mismatch" }
        val interrupted = properties.getProperty("wasInterrupted")
        check(interrupted == "true" || interrupted == "false")
        return RecordingDraft(id, properties.getProperty("createdAtMs").toLong(),
            RecordingFormat.fromWireValue(properties.getProperty("format")),
            DraftPhase.valueOf(properties.getProperty("phase")),
            properties.getProperty("durationMs").toLong(), properties.getProperty("fileSizeBytes").toLong(),
            interrupted.toBoolean())
    }

    fun write(draft: RecordingDraft) {
        check(directory.mkdirs() || directory.isDirectory)
        val properties = Properties().apply {
            setProperty("version", "1"); setProperty("id", draft.id)
            setProperty("createdAtMs", draft.createdAtMs.toString()); setProperty("format", draft.format.wireName)
            setProperty("phase", draft.phase.name); setProperty("durationMs", draft.durationMs.toString())
            setProperty("fileSizeBytes", draft.fileSizeBytes.toString())
            setProperty("wasInterrupted", draft.wasInterrupted.toString())
        }
        val bytes = ByteArrayOutputStream().apply { properties.store(this, null) }.toByteArray()
        io.write(file(draft.id), bytes)
    }

    fun delete(id: String) = io.delete(file(id))
    private fun file(id: String): File {
        require(id.matches(Regex("^[A-Za-z0-9_-]+$")))
        return File(directory, "$id.draft")
    }
}

internal data class ReadyRecording(val draft: RecordingDraft, val file: File) {
    fun toMap(): Map<String, Any> = mapOf("id" to draft.id, "createdAtMs" to draft.createdAtMs,
        "format" to draft.format.wireName, "durationMs" to draft.durationMs,
        "fileSizeBytes" to draft.fileSizeBytes, "wasInterrupted" to draft.wasInterrupted,
        "filePath" to file.absolutePath)
}

internal data class RecoveryBatch(val recordings: List<ReadyRecording>, val unresolvedIds: List<String>)

/** File commit precedes SQLite commit. READY survives until Flutter acknowledges
 * a successful idempotent index transaction. All operations share this monitor.
 */
internal class RecordingSaveProtocol(
    private val root: File,
    private val drafts: RecordingDraftStore,
    private val validate: (File, RecordingFormat) -> Long,
    private val repairMp3: (File, File) -> Unit = Mp3FrameRecovery::copyCompletePrefix,
    private val move: (File, File) -> Boolean = { from, to -> from.renameTo(to) },
    private val deleteFile: (File) -> Boolean = { it.delete() },
) {
    // A timed-out writer stays leased until process exit: recovery cannot touch it.
    private val leases = mutableSetOf<String>()

    @Synchronized fun begin(id: String, createdAtMs: Long, format: RecordingFormat): RecordingDraft {
        check(File(root, "recordings").mkdirs() || File(root, "recordings").isDirectory)
        check(File(root, "recovery").mkdirs() || File(root, "recovery").isDirectory)
        check(id !in drafts.ids() && !completed(id, format).exists() && !temporary(id, format).exists())
        val draft = RecordingDraft(id, createdAtMs, format)
        drafts.write(draft) // Must precede encoder allocation and audio writes.
        leases.add(id)
        return draft
    }

    @Synchronized fun releaseLease(id: String) { leases.remove(id) }

    @Synchronized fun finish(id: String, acceptedDurationMs: Long?): ReadyRecording {
        val draft = drafts.read(id)
        check(draft.phase == DraftPhase.CAPTURING)
        drafts.write(draft.copy(phase = DraftPhase.FINALIZING))
        val file = temporary(id, draft.format)
        sync(file)
        val duration = validate(file, draft.format)
        check(duration > 0)
        if (draft.format == RecordingFormat.MP3) {
            check(acceptedDurationMs != null && acceptedDurationMs > 0 &&
                kotlin.math.abs(duration - acceptedDurationMs) <= 100) { "MP3 sample duration mismatch" }
        }
        return commitFile(draft, file, duration, interrupted = false)
    }

    @Synchronized fun markDiscarding(id: String) {
        val draft = drafts.read(id)
        check(draft.phase == DraftPhase.CAPTURING || draft.phase == DraftPhase.DISCARDING)
        drafts.write(draft.copy(phase = DraftPhase.DISCARDING)) // Before stopping/deleting anything.
    }

    @Synchronized fun discard(id: String) {
        check(id !in leases) { "Recording writer is still active" }
        val draft = drafts.read(id)
        check(draft.phase == DraftPhase.DISCARDING)
        // A cancellation never commits a final file. Retain suspicious conflicts.
        check(!completed(id, draft.format).exists()) { "Cancelled recording has a conflicting final file" }
        remove(temporary(id, draft.format)); remove(repairFile(id))
        drafts.delete(id) // Delete the tombstone last, including on retry after a crash.
    }

    @Synchronized fun acknowledge(id: String) {
        if (id !in drafts.ids()) return // Duplicate acknowledgement after cleanup is safe.
        val draft = drafts.read(id)
        check(draft.phase == DraftPhase.READY && id !in leases)
        check(completed(id, draft.format).isFile) { "Committed recording is missing" }
        remove(temporary(id, draft.format)); remove(repairFile(id))
        drafts.delete(id)
    }

    @Synchronized fun recover(): RecoveryBatch {
        val ready = mutableListOf<ReadyRecording>()
        val unresolved = mutableListOf<String>()
        val ids = drafts.ids()
        for (id in ids) {
            if (id in leases) continue
            try { recoverOne(id)?.let(ready::add) }
            catch (_: Exception) { unresolved.add(id) }
        }
        // Legacy/untracked residuals have no trustworthy cancellation intent or
        // creation metadata. Report and retain them; never infer a saved entry.
        val knownFiles = ids.filter { it.matches(Regex("^[A-Za-z0-9_-]+$")) }
            .flatMap { id -> RecordingFormat.entries.map { it.temporaryFileName(id) } }.toSet()
        File(root, "recovery").listFiles()?.filter { it.name.endsWith(".part") && it.name !in knownFiles }
            ?.forEach { unresolved.add(it.name) }
        return RecoveryBatch(ready, unresolved)
    }

    @Synchronized fun recoverOne(id: String): ReadyRecording? {
        check(id !in leases) { "Recording writer is still active" }
        val draft = drafts.read(id)
        if (draft.phase == DraftPhase.DISCARDING) { discard(id); return null }
        val final = completed(id, draft.format)
        if (draft.phase == DraftPhase.READY) {
            check(final.isFile && final.length() == draft.fileSizeBytes)
            check(kotlin.math.abs(validate(final, draft.format) - draft.durationMs) <= 100)
            return ReadyRecording(draft, final)
        }
        // If a rename completed before the READY update, use only that final file.
        if (final.exists()) {
            check(draft.phase == DraftPhase.VALIDATED) { "Conflicting final recording" }
            val duration = validate(final, draft.format)
            check(final.length() == draft.fileSizeBytes && kotlin.math.abs(duration - draft.durationMs) <= 100)
            val ready = draft.copy(phase = DraftPhase.READY)
            drafts.write(ready)
            return ReadyRecording(ready, final)
        }
        val source = temporary(id, draft.format)
        val interrupted = draft.wasInterrupted || draft.phase != DraftPhase.VALIDATED
        val candidate = if (interrupted && draft.format == RecordingFormat.MP3) {
            val repair = repairFile(id)
            remove(repair)
            repairMp3(source, repair)
            repair
        } else source
        sync(candidate)
        val duration = validate(candidate, draft.format)
        check(duration > 0)
        if (draft.phase == DraftPhase.VALIDATED) {
            check(candidate.length() == draft.fileSizeBytes && kotlin.math.abs(duration - draft.durationMs) <= 100)
        }
        return commitFile(draft, candidate, duration, interrupted)
    }

    private fun commitFile(draft: RecordingDraft, source: File, duration: Long, interrupted: Boolean): ReadyRecording {
        val validated = draft.copy(phase = DraftPhase.VALIDATED, durationMs = duration,
            fileSizeBytes = source.length(), wasInterrupted = interrupted)
        drafts.write(validated)
        val final = completed(draft.id, draft.format)
        check(!final.exists()) { "Refusing to overwrite a recording" }
        check(move(source, final)) { "Unable to commit recording file" }
        val ready = validated.copy(phase = DraftPhase.READY)
        drafts.write(ready)
        return ReadyRecording(ready, final)
    }

    fun temporary(id: String, format: RecordingFormat) = File(File(root, "recovery"), format.temporaryFileName(id))
    fun completed(id: String, format: RecordingFormat) = File(File(root, "recordings"), format.completedFileName(id))
    private fun repairFile(id: String) = File(File(root, "recovery"), "${RecordingFormat.MP3.completedFileName(id)}.repair")
    private fun remove(file: File) { check(!file.exists() || deleteFile(file)) { "Unable to remove recording residual" } }
    private fun sync(file: File) {
        check(file.isFile && file.length() > 0) { "Recording has no audio file" }
        FileOutputStream(file, true).use { it.fd.sync() }
    }
}
