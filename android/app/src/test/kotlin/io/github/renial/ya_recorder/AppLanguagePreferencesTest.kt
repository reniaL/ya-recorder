package io.github.renial.ya_recorder

import org.junit.Assert.assertEquals
import org.junit.Test

class AppLanguagePreferencesTest {
    @Test fun acceptsSupportedLanguages() {
        assertEquals("zh", AppLanguagePreferences.requireSupported("zh"))
        assertEquals("en", AppLanguagePreferences.requireSupported("en"))
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsUnsupportedLanguage() {
        AppLanguagePreferences.requireSupported("fr")
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsMissingLanguage() {
        AppLanguagePreferences.requireSupported(null)
    }
}
