package io.github.renial.ya_recorder

import org.junit.Assert.*
import org.junit.Test

class BackupForegroundGateTest {
    private var focused = false
    private var timeout: (() -> Unit)? = null
    private var cancelled = 0
    private var starts = 0
    private val failures = mutableListOf<String>()
    private val gate = BackupForegroundGate({ focused }) { callback ->
        timeout = callback
        val cancel: () -> Unit = { cancelled++ }
        cancel
    }
    private fun submit() = gate.submit({ starts++ }, { failures.add(it) })

    @Test fun focusedUserCommandStartsImmediately() {
        focused = true
        submit()
        assertEquals(1, starts)
        assertNull(timeout)
    }

    @Test fun pickerReturnWaitsForFocusAndRunsOnlyOnce() {
        submit()
        gate.onReadyChanged()
        assertEquals(0, starts)
        focused = true
        gate.onReadyChanged()
        gate.onReadyChanged()
        timeout!!() // Even an already dispatched timeout must not fail a started command.
        assertEquals(1, starts)
        assertEquals(1, cancelled)
        assertTrue(failures.isEmpty())
    }

    @Test fun timeoutNeverStartsLaterWhenAppReturns() {
        submit()
        timeout!!()
        focused = true
        gate.onReadyChanged()
        assertEquals(0, starts)
        assertEquals(listOf("backup-foreground-timeout"), failures)
        submit()
        assertEquals(1, starts)
    }

    @Test fun detachedActivityFailsPendingCommandOnceAndCannotRestart() {
        submit()
        gate.dispose()
        timeout!!()
        focused = true
        gate.onReadyChanged()
        assertEquals(0, starts)
        assertEquals(1, cancelled)
        assertEquals(listOf("backup-activity-detached"), failures)
        submit()
        assertEquals(0, starts)
        assertEquals(2, failures.size)
    }

    @Test fun secondCommandCannotReplaceWaitingCommand() {
        submit()
        submit()
        assertEquals(listOf("backup-start-pending"), failures)
        focused = true
        gate.onReadyChanged()
        assertEquals(1, starts)
    }
}
