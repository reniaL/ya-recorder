package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Test

class BackupImportSummaryTest {
    @Test fun keepsPreviewAndResultCountsSeparateFromCommitAuthority() {
        val fields = BackupImportSummary(1, 2, 3, 4).fields()
        assertEquals(1, fields["recordingCount"])
        assertEquals(2, fields["folderCount"])
        assertEquals(3, fields["duplicateCount"])
        assertEquals(4, fields["conflictCount"])
        assertEquals(true, fields["importSummaryKnown"])
        assertFalse(fields.containsKey("accepted"))
    }
    @Test fun rejectsNegativeOversizedAndInconsistentCounts() {
        for (values in listOf(listOf(-1, 0, 0, 0), listOf(0, 10001, 0, 0), listOf(9999, 0, 1, 1))) {
            assertThrows(IllegalArgumentException::class.java) { BackupImportSummary(values[0], values[1], values[2], values[3]) }
        }
    }
}
