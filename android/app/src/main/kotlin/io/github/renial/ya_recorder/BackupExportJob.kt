package io.github.renial.ya_recorder

import java.io.File

internal data class BackupExportJob(val metadata: ByteArray, val createdAt: String, val folderCount: Int, val sources: List<BackupExportSource>) {
    companion object {
        fun fromMap(map: Map<*, *>): BackupExportJob {
            val metadata = (map["metadataJson"] as String).toByteArray(Charsets.UTF_8)
            require(metadata.size <= BackupZipExporter.MAX_JSON_BYTES)
            val items = map["sources"] as List<*>
            require(items.size <= 10000)
            val sources = items.map { raw ->
                val source = raw as Map<*, *>
                BackupExportSource(source["path"] as String, File(source["filePath"] as String), (source["size"] as Number).toLong())
            }
            return BackupExportJob(metadata, map["createdAt"] as String, (map["folderCount"] as Number).toInt(), sources)
        }
    }
}
