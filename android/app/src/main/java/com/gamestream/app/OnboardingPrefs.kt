package com.gamestream.app

import android.content.Context

object OnboardingPrefs {
    private const val PREFS = "gamestream"
    private const val INTRO = "intro_completed"

    fun isIntroDone(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(INTRO, false)

    fun markIntroDone(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(INTRO, true)
            .apply()
    }
}
