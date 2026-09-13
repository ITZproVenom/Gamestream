package com.gamestream.app

import android.content.Context

object OnboardingPrefs {
    private const val PREFS = "gamestream"
    private const val KEY_INTRO = "intro_completed_v1"

    fun hasCompletedIntro(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_INTRO, false)

    fun markIntroDone(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_INTRO, true)
            .apply()
    }
}
