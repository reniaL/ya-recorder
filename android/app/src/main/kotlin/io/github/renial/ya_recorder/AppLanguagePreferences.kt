package io.github.renial.ya_recorder

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/** Notification locale is independent of the device locale and never recreates the Activity. */
object AppLanguagePreferences {
    fun requireSupported(code: String?): String = when (code) {
        "zh", "en" -> code
        else -> throw IllegalArgumentException("Unsupported app language")
    }

    fun save(context: Context, code: String) {
        requireSupported(code)
        check(context.getSharedPreferences("app_language", Context.MODE_PRIVATE)
            .edit().putString("language", code).commit()) { "Unable to save notification language" }
    }

    fun localizedContext(context: Context): Context {
        val code = context.getSharedPreferences("app_language", Context.MODE_PRIVATE)
            .getString("language", "zh") ?: "zh"
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocale(if (code == "en") Locale.ENGLISH else Locale.SIMPLIFIED_CHINESE)
        return context.createConfigurationContext(configuration)
    }
}
