package io.github.renial.ya_recorder

import android.content.Context
import android.util.AtomicFile
import java.io.File

internal object AndroidRecordingPersistence {
    @Volatile private var protocol: RecordingSaveProtocol? = null
    @Synchronized fun get(context: Context): RecordingSaveProtocol {
        protocol?.let { return it }
        val root = File(context.applicationContext.filesDir, "ya_recorder")
        return RecordingSaveProtocol(root, RecordingDraftStore(File(root, "recovery"), AtomicDraftIo),
            AndroidRecordingMedia::validate).also { protocol = it }
    }
}

private object AtomicDraftIo : DraftIo {
    override fun read(file: File): ByteArray = AtomicFile(file).openRead().use { it.readBytes() }
    override fun write(file: File, data: ByteArray) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try {
            stream.write(data)
            atomic.finishWrite(stream)
            // AtomicFile logs certain failures instead of throwing; require readback.
            check(atomic.openRead().use { it.readBytes() }.contentEquals(data)) { "Draft commit failed" }
        } catch (error: Exception) {
            atomic.failWrite(stream)
            throw error
        }
    }
    override fun delete(file: File) {
        AtomicFile(file).delete()
        check(!file.exists() && !File(file.path + ".bak").exists() && !File(file.path + ".new").exists())
    }
}
