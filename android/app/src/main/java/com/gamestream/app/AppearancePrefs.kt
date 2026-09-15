package com.gamestream.app

import android.content.Context

class AppearancePrefs(context: Context) {
    private val prefs = context.getSharedPreferences("gamestream.appearance", Context.MODE_PRIVATE)

    var mode: String
        get() = prefs.getString("mode", "dark") ?: "dark"
        set(value) { prefs.edit().putString("mode", value).apply() }

    var accent: String
        get() = prefs.getString("accent", "violet") ?: "violet"
        set(value) { prefs.edit().putString("accent", value).apply() }

    var background: String
        get() = prefs.getString("background", "aurora") ?: "aurora"
        set(value) { prefs.edit().putString("background", value).apply() }

    var cardStyle: String
        get() = prefs.getString("card", "poster") ?: "poster"
        set(value) { prefs.edit().putString("card", value).apply() }

    var density: String
        get() = prefs.getString("density", "comfortable") ?: "comfortable"
        set(value) { prefs.edit().putString("density", value).apply() }

    var animation: String
        get() = prefs.getString("animation", "full") ?: "full"
        set(value) { prefs.edit().putString("animation", value).apply() }

    var effects: String
        get() = prefs.getString("effects", "quality") ?: "quality"
        set(value) { prefs.edit().putString("effects", value).apply() }

    var uiSounds: Boolean
        get() = prefs.getBoolean("sounds", true)
        set(value) { prefs.edit().putBoolean("sounds", value).apply() }

    var glassIntensity: Float
        get() = prefs.getFloat("glass", 1f)
        set(value) { prefs.edit().putFloat("glass", value).apply() }
}
