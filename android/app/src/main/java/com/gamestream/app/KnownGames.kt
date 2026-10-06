package com.gamestream.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Every game the user has touched, kept whole.
 *
 * Favourites, recents, the queue and the collections all stored nothing but
 * a product id and looked the rest up in the live catalogue. Anything the
 * current Game Pass response does not carry - a game that left the service, a
 * page that failed to load, the seed list being replaced by the live one -
 * silently disappeared from the user's own library.
 *
 * So whenever a game is favourited, queued, opened or played, a full copy is
 * written down here. [GameCatalog.find] falls back to this table, which means
 * a list can never lose an entry it was told to remember.
 */
class KnownGames private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("gamestream", Context.MODE_PRIVATE)
    private val games = linkedMapOf<String, CatalogGame>()

    init {
        load()
        GameCatalog.fallback = { id -> get(id) }
    }

    fun get(id: String): CatalogGame? = games[id.uppercase()]

    fun remember(game: CatalogGame) {
        val key = game.id.trim().uppercase()
        if (key.isEmpty()) return
        val existing = games[key]
        if (existing == game) return
        games.remove(key)
        games[key] = game
        // Oldest first, so trimming drops the entries nobody has touched in
        // the longest time.
        while (games.size > LIMIT) {
            val oldest = games.keys.firstOrNull() ?: break
            games.remove(oldest)
        }
        save()
    }

    private fun load() {
        val raw = prefs.getString(KEY, null) ?: return
        runCatching {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val row = array.optJSONObject(i) ?: continue
                val id = row.optString("id").trim()
                if (id.isEmpty()) continue
                games[id.uppercase()] = CatalogGame(
                    id = id,
                    slug = row.optString("slug").ifBlank { id.lowercase() },
                    title = row.optString("title").ifBlank { id },
                    tagline = row.optString("tagline"),
                    genre = row.optString("genre").ifBlank { "Cloud" },
                    posterUrl = row.optString("poster").ifBlank { null }
                )
            }
        }
    }

    private fun save() {
        val array = JSONArray()
        games.values.forEach { game ->
            array.put(
                JSONObject()
                    .put("id", game.id)
                    .put("slug", game.slug)
                    .put("title", game.title)
                    .put("tagline", game.tagline)
                    .put("genre", game.genre)
                    .put("poster", game.posterUrl.orEmpty())
            )
        }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    companion object {
        private const val KEY = "known_games_v1"
        private const val LIMIT = 400

        @Volatile private var instance: KnownGames? = null

        fun get(context: Context): KnownGames =
            instance ?: synchronized(this) {
                instance ?: KnownGames(context.applicationContext).also { instance = it }
            }
    }
}
