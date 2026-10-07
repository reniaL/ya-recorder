package io.github.renial.ya_recorder

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Serial control worker keeps encoder drain and native joins off Android's UI.
 * Closing skips queued commands, then releases resources after the active one.
 */
internal class SerialRecordingCommands(
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "recording-control").apply { isDaemon = true }
    },
) {
    @Volatile var isClosed = false
        private set

    @Synchronized fun submit(command: () -> Unit) {
        if (!isClosed) executor.execute { if (!isClosed) command() }
    }

    @Synchronized fun close(cleanup: () -> Unit) {
        if (isClosed) return
        isClosed = true
        executor.execute(cleanup)
        executor.shutdown()
    }
}
