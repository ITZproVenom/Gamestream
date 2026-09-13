package com.gamestream.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class GameCollection(
    val id: String,
    val name: String,
    val gameIds: List<String>
)

class CollectionStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("gamestream", Context.MODE_PRIVATE)

    fun collections(): List<GameCollection> {
        val raw = prefs.getString(KEY, "[]") ?: "[]"
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val idsJson = obj.optJSONArray("gameIds") ?: JSONArray()
                    val ids = buildList {
                        for (j in 0 until idsJson.length()) add(idsJson.getString(j))
                    }
                    add(GameCollection(obj.getString("id"), obj.getString("name"), ids))
                }
            }
        }.getOrDefault(emptyList())
    }

    fun create(name: String): GameCollection? {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return null
        val current = collections().toMutableList()
        current.firstOrNull { it.name.equals(trimmed, ignoreCase = true) }?.let { return it }
        val created = GameCollection(System.currentTimeMillis().toString(), trimmed, emptyList())
        persist(listOf(created) + current)
        return created
    }

    fun delete(id: String) {
        persist(collections().filterNot { it.id == id })
    }

    fun toggle(gameId: String, collectionId: String) {
        persist(collections().map { list ->
            if (list.id != collectionId) list
            else {
                val ids = if (list.gameIds.contains(gameId)) list.gameIds.filter { it != gameId }
                else listOf(gameId) + list.gameIds
                list.copy(gameIds = ids.take(24))
            }
        })
    }

    fun games(collection: GameCollection): List<CatalogGame> =
        collection.gameIds.mapNotNull { id -> GameCatalog.games.find { it.id == id } }

    private fun persist(items: List<GameCollection>) {
        val arr = JSONArray()
        items.take(12).forEach { list ->
            val obj = JSONObject()
            obj.put("id", list.id)
            obj.put("name", list.name)
            val ids = JSONArray()
            list.gameIds.forEach { ids.put(it) }
            obj.put("gameIds", ids)
            arr.put(obj)
        }
        prefs.edit().putString(KEY, arr.toString()).apply()
    }

    companion object {
        private const val KEY = "collections_v1"
    }
}
