package com.gamestream.app

import android.content.Context
import android.content.SharedPreferences

class SearchPrefs(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("gamestream", Context.MODE_PRIVATE)

    fun recent(): List<String> =
        prefs.getString(KEY_RECENT, "")?.split("|")?.filter { it.isNotBlank() } ?: emptyList()

    fun pinned(): List<String> =
        prefs.getString(KEY_PINNED, "")?.split("|")?.filter { it.isNotBlank() } ?: emptyList()

    fun remember(query: String): List<String> {
        val q = query.trim()
        if (q.isEmpty()) return recent()
        val next = (listOf(q) + recent().filter { !it.equals(q, ignoreCase = true) }).take(8)
        prefs.edit().putString(KEY_RECENT, next.joinToString("|")).apply()
        return next
    }

    fun clearRecent() {
        prefs.edit().remove(KEY_RECENT).apply()
    }

    fun togglePin(query: String): List<String> {
        val q = query.trim()
        if (q.isEmpty()) return pinned()
        val current = pinned()
        val next = if (current.any { it.equals(q, ignoreCase = true) }) {
            current.filter { !it.equals(q, ignoreCase = true) }
        } else {
            (listOf(q) + current).take(12)
        }
        prefs.edit().putString(KEY_PINNED, next.joinToString("|")).apply()
        return next
    }

    fun isPinned(query: String): Boolean =
        pinned().any { it.equals(query.trim(), ignoreCase = true) }

    companion object {
        private const val KEY_RECENT = "recent_searches"
        private const val KEY_PINNED = "pinned_searches"
    }
}
