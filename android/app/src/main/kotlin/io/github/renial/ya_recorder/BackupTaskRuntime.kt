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
    private var started = false
    private var cleaning = false
    private var lastProgress = 0L
    @Volatile var onChanged: (() -> Unit)? = null

    init {
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
                worker.execute { try { cleanupInterrupted() } finally { synchronized(this) { executing = false } } }
            }
        }
    }

    @Synchronized fun snapshot(): Map<String, Any?>? = state?.toMap()

    @Synchronized fun prepare(uri: String, direction: String): Map<String, Any?> {
        check(!executing && !cleaning && state?.get("status") !in listOf("prepared", "running")) { "backup-busy" }
        check(state == null || state?.get("released") == true) { "backup-release-required" }
        check(state?.get("residualUri") == null && state?.get("cleanupPending") != true) { "backup-cleanup-pending" }
        require(Uri.parse(uri).scheme == "content") { "document-uri-required" }
        require(direction in listOf("read", "write"))
        val id = UUID.randomUUID().toString()
        val directory = File(root, id).apply { check(mkdir()) }
        state = mutableMapOf("taskId" to id, "sequence" to 0L, "status" to "prepared", "processedBytes" to 0L,
            "directory" to directory.path, "stagedPath" to File(directory, "payload.zip").path,
            "uri" to uri, "direction" to direction)
        persist()
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
        worker.execute {
            try {
                val task = synchronized(this) { requireCurrent(id); state!!.toMap() }
                val uri = Uri.parse(task["uri"] as String)
                val file = File(task["stagedPath"] as String)
                val resolver = context.contentResolver
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
                synchronized(this) {
                    if (cancelReason != null) throw CancellationException()
                    update("completed", null)
                } // Includes successful close, not just flush.
            } catch (error: Exception) {
                synchronized(this) {
                    val reason = cancelReason
                    update(if (reason == "cancelled") "cancelled" else "failed", reason ?: "document-io-failed")
                }
                cleanupFiles(id, deleteTarget = true)
            } finally {
                synchronized(this) { executing = false }
                onChanged?.invoke()
                finished()
            }
        }
    }

    private fun transfer(id: String, input: java.io.InputStream, output: java.io.OutputStream) {
        BackupStreamCopy.copy(input, output, { synchronized(this) { cancelReason != null } }, { bytes ->
            val now = System.nanoTime()
            synchronized(this) {
                requireCurrent(id)
                state!!["processedBytes"] = bytes
                if (now - lastProgress >= 250_000_000L) {
                    lastProgress = now
                    state!!["sequence"] = (state!!["sequence"] as Number).toLong() + 1
                    onChanged?.invoke()
                }
            }
        })
    }

    @Synchronized fun startFailed(id: String) {
        requireCurrent(id)
        update("failed", "service-start-failed")
        worker.execute {
            try { cleanupFiles(id, deleteTarget = true) }
            finally { synchronized(this) { executing = false }; onChanged?.invoke() }
        }
    }

    @Synchronized fun expireUnstarted(id: String) {
        if (state?.get("taskId") == id && state?.get("status") == "running" && !started) startFailed(id)
    }

    @Synchronized fun accept(id: String) {
        requireCurrent(id)
        check(state!!["status"] == "completed")
        state!!["accepted"] = true
        persist()
    }

    fun release(id: String, done: (Exception?) -> Unit) {
        worker.execute {
            try {
                synchronized(this) { requireCurrent(id); check(!executing && state!!["status"] != "running") }
                cleanupFiles(id, deleteTarget = synchronized(this) { state?.get("accepted") != true }, markReleased = true)
                done(null)
            } catch (error: Exception) { done(error) }
        }
    }

    private fun cleanupInterrupted() { cleanupFiles(snapshot()!!["taskId"] as String, deleteTarget = true, markReleased = true); onChanged?.invoke() }

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
            task["cleanupPending"] = !File(root, id).let { !it.exists() || it.deleteRecursively() }
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

    companion object {
        @Volatile private var instance: BackupTaskRuntime? = null
        fun get(context: Context): BackupTaskRuntime = instance ?: synchronized(this) {
            instance ?: BackupTaskRuntime(context.applicationContext).also { instance = it }
        }
    }
}
