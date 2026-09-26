package com.gamestream.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue

class AppearancePrefs(context: Context) {
    private val prefs = context.getSharedPreferences("gamestream.appearance", Context.MODE_PRIVATE)

    var revision by mutableIntStateOf(0)
        private set

    private fun bump() {
        revision += 1
    }

    var mode: String
        get() = prefs.getString("mode", "dark") ?: "dark"
        set(value) { prefs.edit().putString("mode", value).apply(); bump() }

    var accent: String
        get() = prefs.getString("accent", "violet") ?: "violet"
        set(value) { prefs.edit().putString("accent", value).apply(); bump() }

    var background: String
        get() = prefs.getString("background", "aurora") ?: "aurora"
        set(value) { prefs.edit().putString("background", value).apply(); bump() }

    var customBgColor: String
        get() = prefs.getString("customBg", "deepBlack") ?: "deepBlack"
        set(value) { prefs.edit().putString("customBg", value).apply(); bump() }

    var backgroundDim: Float
        get() = prefs.getFloat("bgDim", 0.45f)
        set(value) { prefs.edit().putFloat("bgDim", value).apply(); bump() }

    var cardStyle: String
        get() = prefs.getString("card", "poster") ?: "poster"
        set(value) { prefs.edit().putString("card", value).apply(); bump() }

    var density: String
        get() = prefs.getString("density", "comfortable") ?: "comfortable"
        set(value) { prefs.edit().putString("density", value).apply(); bump() }

    var hubLayout: String
        get() = prefs.getString("hubLayout", "editorial") ?: "editorial"
        set(value) { prefs.edit().putString("hubLayout", value).apply(); bump() }

    var animation: String
        get() = prefs.getString("animation", "full") ?: "full"
        set(value) { prefs.edit().putString("animation", value).apply(); bump() }

    var effects: String
        get() = prefs.getString("effects", "quality") ?: "quality"
        set(value) { prefs.edit().putString("effects", value).apply(); bump() }

    var uiSounds: Boolean
        get() = prefs.getBoolean("sounds", true)
        set(value) { prefs.edit().putBoolean("sounds", value).apply(); bump() }

    var controllerHaptics: Boolean
        get() = prefs.getBoolean("controllerHaptics", true)
        set(value) { prefs.edit().putBoolean("controllerHaptics", value).apply(); bump() }

    /** 0.5f … 3.0f — default 1.6f for weak wired pads. */
    var rumbleIntensity: Float
        get() = prefs.getFloat("rumbleIntensity", 1.6f).coerceIn(0.5f, 3f)
        set(value) { prefs.edit().putFloat("rumbleIntensity", value.coerceIn(0.5f, 3f)).apply(); bump() }

    var showActivityOnHome: Boolean
        get() = prefs.getBoolean("showActivity", true)
        set(value) { prefs.edit().putBoolean("showActivity", value).apply(); bump() }

    var showGenreFilters: Boolean
        get() = prefs.getBoolean("showGenres", true)
        set(value) { prefs.edit().putBoolean("showGenres", value).apply(); bump() }

    var glassIntensity: Float
        get() = prefs.getFloat("glass", 1f)
        set(value) { prefs.edit().putFloat("glass", value).apply(); bump() }

    fun sectionSpacingDp(): Int = when (density) {
        "spacious" -> 28
        "compact" -> 12
        else -> 18
    }

    fun posterWidthFraction(): Float = when {
        density == "compact" || cardStyle == "compact" -> 0.28f
        cardStyle == "wide" -> 0.42f
        density == "spacious" -> 0.36f
        else -> 0.32f
    }

    fun backgroundColorArgb(): Int = when (background) {
        "solid", "customColor" -> when (customBgColor) {
            "charcoal" -> 0xFF1E1E24.toInt()
            "navy" -> 0xFF0F1A38.toInt()
            "forest" -> 0xFF0D241A.toInt()
            "plum" -> 0xFF240F2E.toInt()
            "wine" -> 0xFF2E0D1A.toInt()
            "slate" -> 0xFF1A1E29.toInt()
            "white" -> 0xFFF5F5FA.toInt()
            else -> 0xFF0A0A12.toInt()
        }
        "midnight" -> 0xFF050514.toInt()
        "dusk" -> 0xFF140A1F.toInt()
        "mesh" -> 0xFF0C0C18.toInt()
        else -> 0xFF0A0A12.toInt()
    }
}
