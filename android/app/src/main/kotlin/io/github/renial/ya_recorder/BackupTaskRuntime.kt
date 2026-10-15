package io.github.renial.ya_recorder

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors

/** Process-owned worker. Never opens SQLite; Dart remains the only library writer. */
internal class BackupTaskRuntime private constructor(private val context: Context) {
    private val root = File(context.filesDir, "backup-transfers").apply { mkdirs() }
    private val journal = AtomicFile(File(root, "transfer.json"))
    private val worker = Executors.newSingleThreadExecutor()
    private var state: MutableMap<String, Any?>? = null
    private var cancelReason: String? = null
    private var executing = false
    private var serviceActive = false
    private var started = false
    private var cleaning = false
    private var lastProgress = 0L
    private var exportJob: BackupExportJob? = null
    private var placement: List<Pair<File, File>>? = null
    @Volatile var onChanged: (() -> Unit)? = null

    init {
        worker.execute { pruneExpiredExports() }
        if (journal.baseFile.exists()) {
            state = JSONObject(journal.openRead().use { it.readBytes().toString(Charsets.UTF_8) }).let { json ->
                json.keys().asSequence().associateWith { key -> json.get(key).let { if (it == JSONObject.NULL) null else it } }.toMutableMap()
            }
            // No auto-resume, including after reboot. Cleanup is serialized before a new job.
            if (state?.get("status") in listOf("prepared", "running")) {
                state!!["status"] = "interrupted"
                state!!["error"] = "process-interrupted"
                persist()
                executing = true
                worker.execute { try { cleanupAfterFailure(state!!["taskId"] as String, markReleased = true) } finally { synchronized(this) { executing = false } } }
            }
        }
    }

    @Synchronized fun snapshot(): Map<String, Any?>? = state?.toMutableMap()?.also {
        // A second import phase cannot start until the previous worker AND
        // service have closed. In particular, completion polling must not race
        // the old service's posted stopSelf callback.
        if ((executing || serviceActive) && it["status"] in listOf("completed", "cancelled", "failed")) it["status"] = "running"
    }

    @Synchronized fun serviceStopped() { serviceActive = false }

    @Synchronized fun prepare(uri: String, direction: String, displayName: String? = null): Map<String, Any?> {
        check(!executing && !cleaning && state?.get("status") !in listOf("prepared", "running")) { "backup-busy" }
        check(state == null || state?.get("released") == true) { "backup-release-required" }
        check(state?.get("residualUri") == null && state?.get("cleanupPending") != true) { "backup-cleanup-pending" }
        require(Uri.parse(uri).scheme == "content") { "document-uri-required" }
        require(direction in listOf("read", "write"))
        val id = UUID.randomUUID().toString()
        val directory = File(root, id).apply { check(mkdir()) }
        state = mutableMapOf("taskId" to id, "sequence" to 0L, "status" to "prepared", "processedBytes" to 0L,
            "directory" to directory.path, "stagedPath" to File(directory, "payload.zip").path,
            "uri" to uri, "direction" to direction, "displayName" to displayName?.take(4096))
        persist()
        worker.execute { pruneExpiredExports() }
        return state!!.toMap()
    }

    @Synchronized fun reserve(id: String, direction: String, uri: String) {
        requireCurrent(id)
        check(state!!["status"] == "prepared" && !executing) { "backup-busy" }
        require(direction == "read" || direction == "write")
        require(Uri.parse(uri).scheme == "content") { "document-uri-required" }
        require(state!!["uri"] == uri && state!!["direction"] == direction) { "document-selection-mismatch" }
        if (direction == "write") check(File(state!!["stagedPath"] as String).isFile) { "staged-file-missing" }
        if (direction == "write") state!!["totalBytes"] = File(state!!["stagedPath"] as String).length()
        state!!["direction"] = direction
        state!!["uri"] = uri
        state!!["status"] = "running"
        cancelReason = null
        executing = true
        started = false
        persist()
    }

    @Synchronized fun reserveExport(id: String, job: BackupExportJob) {
        requireCurrent(id)
        check(state!!["status"] == "prepared" && state!!["direction"] == "write" && !executing)
        exportJob = job
        state!!["kind"] = "export"
        state!!["recordingCount"] = job.sources.size
        state!!["folderCount"] = job.folderCount
        state!!["stage"] = "preparing"
        state!!["status"] = "running"
        cancelReason = null
        executing = true
        started = false
        persist()
    }

    @Synchronized fun reserveImport(id: String, files: List<Map<*, *>>? = null) {
        requireCurrent(id)
        check(!executing && state!!["direction"] == "read")
        if (files == null) {
            check(state!!["status"] == "prepared")
            state!!["kind"] = "import"
        } else {
            check(state!!["status"] == "completed" && state!!["kind"] == "import")
            require(files.size <= 10000)
            val extracted = File(File(state!!["stagedPath"] as String).parentFile, "extracted")
            placement = files.map {
                val name = it["name"] as String
                require(Regex("recording-[A-Za-z0-9_-]{1,128}\\.(aac|mp3|m4a)").matches(name))
                File(extracted, name) to File(it["target"] as String)
            }
            state!!["stage"] = "importing"
        }
        state!!["processedBytes"] = 0L
        state!!["processedRecordings"] = 0
        state!!["totalBytes"] = null
        state!!["status"] = "running"
        cancelReason = null; executing = true; started = false
        persist()
    }

    @Synchronized fun cancel(id: String, reason: String = "cancelled") {
        if (state?.get("taskId") == id && state?.get("status") == "running" && cancelReason == null) {
            cancelReason = reason
            state!!["cancelRequested"] = true
            state!!["sequence"] = (state!!["sequence"] as Number).toLong() + 1
        }
    }

    @Synchronized fun execute(id: String, finished: () -> Unit) {
        requireCurrent(id)
        check(executing && !started && state!!["status"] == "running")
        started = true
        serviceActive = true
        worker.execute job@{
            try {
                val task = synchronized(this) { requireCurrent(id); state!!.toMap() }
                val uri = Uri.parse(task["uri"] as String)
                val file = File(task["stagedPath"] as String)
                val resolver = context.contentResolver
                if (task["kind"] == "import" && placement != null) {
                    BackupZipImporter.place(requireNotNull(placement),
                        { synchronized(this) { cancelReason != null } },
                        { reportProgress(id, it.stage, it.bytes, it.total, it.recordings) })
                    synchronized(this) { update("completed", null) }
                    return@job
                }
                if (task["kind"] == "export") {
                    val job = synchronized(this) { requireNotNull(exportJob) }
                    val size = BackupZipExporter.create(file, job.sources, job.metadata, job.createdAt, job.folderCount,
                        { synchronized(this) { cancelReason != null } }, { progress ->
                            reportProgress(id, progress.stage, progress.bytes, progress.total, progress.recordings)
                        })
                    reportProgress(id, "saving", 0, size, 0)
                    synchronized(this) { state!!["archiveVerified"] = true; persist() }
                }
                if (task["direction"] == "read") {
                    (resolver.openInputStream(uri) ?: error("source-open-failed")).use { input ->
                        file.outputStream().use { output -> transfer(id, input, output) }
                    }
                } else {
                    synchronized(this) {
                        state!!["targetTouched"] = true
                        persist() // Must precede a provider opening/truncating the destination.
                    }
                    file.inputStream().use { input ->
                        (resolver.openOutputStream(uri, "wt") ?: error("target-open-failed")).use { output -> transfer(id, input, output) }
                    }
                }
                if (task["kind"] == "import") {
                    val extracted = File(file.parentFile, "extracted")
                    val entries = BackupZipImporter.extract(file, extracted,
                        { synchronized(this) { cancelReason != null } },
                        { reportProgress(id, it.stage, it.bytes, it.total, it.recordings) })
                    val report = JSONObject().put("manifest", File(extracted, "manifest.json").readText())
                        .put("metadata", File(extracted, "metadata.json").readText())
                        .put("entries", org.json.JSONArray(entries.map { JSONObject().put("path", it.path).put("size", it.size).put("sha256", it.sha256) }))
                    File(file.parentFile, "verified.json").writeText(report.toString())
                }
                synchronized(this) {
                    if (cancelReason != null) throw CancellationException()
                    if (task["kind"] == "export") {
                        // Fully verified archive + successful provider close is the
                        // authority even if the Flutter engine disappeared meanwhile.
                        state!!["accepted"] = true
                        state!!["cachedArchivePath"] = file.path
                        state!!["retainedUntilMs"] = System.currentTimeMillis() + RETAIN_MILLIS
                    }
                    update("completed", null)
                } // Includes successful close, not just flush.
            } catch (error: Exception) {
                synchronized(this) {
                    val reason = cancelReason
                    state!!["accepted"] = false
                    state!!["cachedArchivePath"] = null
                    state!!["retainedUntilMs"] = 0L
                    state!!["errorDetail"] = error.message
                    // Disk-full may also prevent journaling. Keep in-memory failure,
                    // free our artifacts, then retry persistence during cleanup.
                    runCatching { update(if (reason == "cancelled") "cancelled" else "failed", reason ?: if (error is SecurityException) "document-permission-denied" else "backup-export-or-io-failed") }
                }
                cleanupAfterFailure(id)
            } finally {
                synchronized(this) { executing = false; exportJob = null; placement = null }
                onChanged?.invoke()
                finished()
            }
        }
    }

    private fun transfer(id: String, input: java.io.InputStream, output: java.io.OutputStream) {
        BackupStreamCopy.copy(input, output, { synchronized(this) { cancelReason != null } }, { bytes ->
            val snapshot = snapshot()!!
            reportProgress(id, snapshot["stage"] as? String ?: if (snapshot["direction"] == "read") "checking" else "saving",
                bytes, (snapshot["totalBytes"] as? Number)?.toLong(), 0)
        }, limit = if (snapshot()?.get("kind") == "import") 0xfffffffeL else BackupStreamCopy.MAX_BYTES)
    }

    @Synchronized private fun reportProgress(id: String, stage: String, bytes: Long, total: Long?, recordings: Int) {
        requireCurrent(id)
        val stageChanged = state!!["stage"] != stage
        state!!["stage"] = stage
        state!!["processedBytes"] = bytes
        state!!["totalBytes"] = total
        state!!["processedRecordings"] = recordings
        val now = System.nanoTime()
        if (stageChanged || now - lastProgress >= 250_000_000L || bytes == total) {
            lastProgress = now
            state!!["sequence"] = (state!!["sequence"] as Number).toLong() + 1
            onChanged?.invoke()
        }
    }

    @Synchronized fun startFailed(id: String) {
        if (state?.get("taskId") != id || state?.get("status") != "running") return
        runCatching { update("failed", "service-start-failed") }
        worker.execute {
            try { cleanupAfterFailure(id) }
            finally { synchronized(this) { executing = false }; onChanged?.invoke() }
        }
    }

    @Synchronized fun expireUnstarted(id: String, sequence: Long) {
        if (state?.get("taskId") == id && state?.get("status") == "running" &&
            (state?.get("sequence") as? Number)?.toLong() == sequence && !started) startFailed(id)
    }

    @Synchronized fun accept(id: String) {
        requireCurrent(id)
        check(state!!["status"] == "completed")
        state!!["accepted"] = true
        persist()
    }

    @Synchronized fun recordImportSummary(id: String, summary: BackupImportSummary) {
        requireCurrent(id)
        check(state!!["kind"] == "import" && state!!["status"] == "completed" && !executing)
        state!!.putAll(summary.fields())
        persist()
    }

    fun release(id: String, done: (Exception?) -> Unit) {
        worker.execute {
            try {
                synchronized(this) { requireCurrent(id); check(!executing && state!!["status"] != "running") }
                cleanupFiles(id, deleteTarget = synchronized(this) { state?.get("accepted") != true }, markReleased = true)
                done(null)
            } catch (error: Exception) {
                val committed = synchronized(this) {
                    if (state?.get("taskId") == id && state?.get("kind") == "export" && state?.get("accepted") == true) {
                        state!!["cleanupPending"] = true
                        state!!["cleanupError"] = error.message
                        runCatching { persist() }
                        true
                    } else false
                }
                done(if (committed) null else error)
            }
        }
    }

    private fun cleanupAfterFailure(id: String, markReleased: Boolean = false) {
        try { cleanupFiles(id, deleteTarget = true, markReleased = markReleased) }
        catch (error: Exception) {
            synchronized(this) {
                if (state?.get("taskId") != id) return
                state!!["cleanupPending"] = true
                state!!["cleanupError"] = error.message
                if (state!!["direction"] == "write" && state!!["targetRemoved"] != true) state!!["residualUri"] = state!!["uri"]
                runCatching { persist() }
            }
        }
    }

    private fun cleanupFiles(taskId: String, deleteTarget: Boolean, markReleased: Boolean = false) {
        val task = synchronized(this) {
            requireCurrent(taskId)
            cleaning = true
            state!!.toMutableMap()
        }
        try {
            if (deleteTarget && task["direction"] == "write" && task["targetRemoved"] != true) {
                val uri = Uri.parse(task["uri"] as String)
                val deleted = try { DocumentsContract.deleteDocument(context.contentResolver, uri) } catch (_: Exception) { false }
                task["residualUri"] = if (deleted) null else uri.toString()
                task["targetRemoved"] = deleted
            }
            // Derive ownership from UUID, never trust a persisted arbitrary filesystem path.
            val id = UUID.fromString(task["taskId"] as String).toString()
            val directory = File(root, id)
            val retainedUntil = (task["retainedUntilMs"] as? Number)?.toLong() ?: 0
            if (task["accepted"] == true && task["kind"] == "export" && retainedUntil > System.currentTimeMillis()) {
                File(directory, ".retain-until").writeText(retainedUntil.toString())
                task["cleanupPending"] = false
            } else {
                task["cleanupPending"] = !directory.let { !it.exists() || it.deleteRecursively() }
                task["cachedArchivePath"] = null
            }
            if (task["status"] == "prepared") task["status"] = "cancelled"
            if (markReleased) task["released"] = true
            task["sequence"] = (task["sequence"] as Number).toLong() + 1
            synchronized(this) {
                requireCurrent(taskId)
                state = task
                persist()
            }
        } finally { synchronized(this) { cleaning = false } }
    }

    @Synchronized private fun requireCurrent(id: String) { check(state?.get("taskId") == id) { "stale-backup-task" } }
    private fun update(status: String, error: String?) {
        state!!["status"] = status
        state!!["error"] = error
        state!!["sequence"] = (state!!["sequence"] as Number).toLong() + 1
        persist()
    }
    private fun persist() {
        val stream = journal.startWrite()
        try { stream.write(JSONObject(state!!).toString().toByteArray()); journal.finishWrite(stream) }
        catch (error: Exception) { journal.failWrite(stream); throw error }
    }

    private fun pruneExpiredExports() {
        for (directory in root.listFiles().orEmpty()) {
            try {
            if (!directory.isDirectory || runCatching { UUID.fromString(directory.name).toString() }.getOrNull() != directory.name) continue
            val marker = File(directory, ".retain-until")
            val expires = runCatching { marker.readText().toLong() }.getOrNull() ?: continue
            if (expires <= System.currentTimeMillis()) {
                val payload = File(directory, "payload.zip")
                // Keep the receipt when a share consumer still holds the file.
                if (!payload.exists() || payload.delete()) {
                    if (directory.listFiles().orEmpty().all { it.name == marker.name }) {
                        marker.delete()
                        if (!directory.delete() && directory.exists()) marker.writeText(expires.toString())
                    }
                }
            }
            } catch (_: Exception) { /* Preserve receipt and retry on next prepare/startup. */ }
        }
    }

    companion object {
        private const val RETAIN_MILLIS = 24 * 60 * 60 * 1000L
        @Volatile private var instance: BackupTaskRuntime? = null
        fun get(context: Context): BackupTaskRuntime = instance ?: synchronized(this) {
            instance ?: BackupTaskRuntime(context.applicationContext).also { instance = it }
        }
    }
}
