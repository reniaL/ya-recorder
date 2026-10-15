package io.github.renial.ya_recorder

import java.util.UUID

/** startForegroundService returns before the serial recorder worker runs.
 * Keep that interval non-idle, including across Flutter/Activity reattachment.
 */
internal class RecordingStartReservations {
    private val pending = linkedMapOf<String, String>()

    @Synchronized fun reserve(format: String): String = UUID.randomUUID().toString().also {
        pending[it] = format
    }

    @Synchronized fun complete(token: String?) {
        if (token != null) pending.remove(token)
    }

    @Synchronized fun status(current: () -> Map<String, Any?>): Map<String, Any?> {
        // Read volatile service state inside the reservation lock, never before
        // a completed reservation's latest state becomes visible.
        val value = current()
        val format = pending.values.firstOrNull() ?: return value
        if (value["state"] != "idle" && value["state"] != "failed") return value
        return mapOf("state" to "preparing", "elapsedMs" to 0L,
            "canResume" to false, "sessionId" to null, "format" to format)
    }
}
