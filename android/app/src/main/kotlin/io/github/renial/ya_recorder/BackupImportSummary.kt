package io.github.renial.ya_recorder

/** Bounded receipt only. SQLite's commit marker remains the commit authority. */
internal data class BackupImportSummary(val recordings: Int, val folders: Int, val duplicates: Int, val conflicts: Int) {
    init {
        require(listOf(recordings, folders, duplicates, conflicts).all { it in 0..10000 })
        require(recordings + duplicates + conflicts <= 10000)
    }
    fun fields(): Map<String, Any> = mapOf("recordingCount" to recordings, "folderCount" to folders,
        "duplicateCount" to duplicates, "conflictCount" to conflicts, "importSummaryKnown" to true)
}
