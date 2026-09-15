package com.gamestream.app

import android.content.Context

class AppearancePrefs(context: Context) {
    private val prefs = context.getSharedPreferences("gamestream.appearance", Context.MODE_PRIVATE)

    var revision: Int = 0
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

    var cardStyle: String
        get() = prefs.getString("card", "poster") ?: "poster"
        set(value) { prefs.edit().putString("card", value).apply(); bump() }

    var density: String
        get() = prefs.getString("density", "comfortable") ?: "comfortable"
        set(value) { prefs.edit().putString("density", value).apply(); bump() }

    var animation: String
        get() = prefs.getString("animation", "full") ?: "full"
        set(value) { prefs.edit().putString("animation", value).apply(); bump() }

    var effects: String
        get() = prefs.getString("effects", "quality") ?: "quality"
        set(value) { prefs.edit().putString("effects", value).apply(); bump() }

    var uiSounds: Boolean
        get() = prefs.getBoolean("sounds", true)
        set(value) { prefs.edit().putBoolean("sounds", value).apply(); bump() }

    var glassIntensity: Float
        get() = prefs.getFloat("glass", 1f)
        set(value) { prefs.edit().putFloat("glass", value).apply(); bump() }
}
