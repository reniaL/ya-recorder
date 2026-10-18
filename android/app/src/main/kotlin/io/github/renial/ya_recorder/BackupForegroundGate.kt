package io.github.renial.ya_recorder

/** Main-thread gate for the focus gap between a document result and its returning window. */
internal class BackupForegroundGate(
    private val ready: () -> Boolean,
    private val scheduleTimeout: (() -> Unit) -> (() -> Unit),
) {
    private class Pending(val run: () -> Unit, val fail: (String) -> Unit) {
        var cancelTimeout: (() -> Unit)? = null
    }
    private var pending: Pending? = null
    private var disposed = false

    fun submit(run: () -> Unit, fail: (String) -> Unit) {
        if (disposed) { fail("backup-activity-detached"); return }
        if (pending != null) { fail("backup-start-pending"); return }
        if (ready()) { run(); return }
        val request = Pending(run, fail)
        pending = request
        request.cancelTimeout = scheduleTimeout {
            if (pending === request) {
                pending = null
                request.fail("backup-foreground-timeout")
            }
        }
    }

    fun onReadyChanged() {
        val request = pending ?: return
        if (!ready()) return
        pending = null
        request.cancelTimeout?.invoke()
        request.run()
    }

    fun dispose() {
        disposed = true
        val request = pending ?: return
        pending = null
        request.cancelTimeout?.invoke()
        request.fail("backup-activity-detached")
    }
}
