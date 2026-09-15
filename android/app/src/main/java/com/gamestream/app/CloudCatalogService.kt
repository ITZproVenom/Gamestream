package com.gamestream.app

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

object CloudCatalogService {
    private const val SIGL =
        "https://catalog.gamepass.com/sigls/v2?id=29a81209-df6f-41fd-a528-2ae6b91f719c&language=en-us&market=US"
    private const val CACHE = "xcloud-catalog-v1.json"
    @Volatile private var started = false

    fun refreshIfNeeded(context: Context) {
        if (started) return
        started = true
        loadCache(context)?.takeIf { it.size >= 20 }?.let { GameCatalog.installLiveCatalog(it) }
    }

    suspend fun fetchAndInstall(context: Context) = withContext(Dispatchers.IO) {
        refreshIfNeeded(context)
        try {
            val remote = fetchRemote()
            if (remote.size >= 20) {
                saveCache(context, remote)
                withContext(Dispatchers.Main) {
                    GameCatalog.installLiveCatalog(remote)
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun fetchRemote(): List<CatalogGame> {
        val raw = JSONArray(httpGet(SIGL))
        val ids = linkedSetOf<String>()
        for (i in 0 until raw.length()) {
            val row = raw.optJSONObject(i) ?: continue
            val id = row.optString("id").trim()
            if (id.isNotEmpty()) ids.add(id)
        }
        val games = mutableListOf<CatalogGame>()
        val list = ids.toList()
        var index = 0
        while (index < list.size) {
            val slice = list.subList(index, minOf(index + 20, list.size))
            index += 20
            games += hydrate(slice)
        }
        return games.distinctBy { it.id.uppercase() }
    }

    private fun hydrate(ids: List<String>): List<CatalogGame> {
        val joined = ids.joinToString(",")
        val url =
            "https://displaycatalog.mp.microsoft.com/v7.0/products?bigIds=$joined&market=US&languages=en-us&MS-CV=GS.1"
        val json = JSONObject(httpGet(url))
        val products = json.optJSONArray("Products") ?: return emptyList()
        val out = mutableListOf<CatalogGame>()
        for (i in 0 until products.length()) {
            val product = products.optJSONObject(i) ?: continue
            val id = product.optString("ProductId").trim()
            if (id.isEmpty()) continue
            val loc = product.optJSONArray("LocalizedProperties")?.optJSONObject(0)
            val title = loc?.optString("ProductTitle")?.trim().orEmpty().ifEmpty { id }
            val tagline = loc?.optString("ShortDescription")?.trim().orEmpty().take(140)
            val props = product.optJSONObject("Properties")
            val genre = props?.optString("Category")?.takeIf { it.isNotBlank() }
                ?: props?.optJSONArray("Categories")?.optString(0)
                ?: "Cloud"
            val images = loc?.optJSONArray("Images")
            out += CatalogGame(
                id = id,
                slug = slugify(title),
                title = title,
                tagline = tagline,
                genre = shortenGenre(genre),
                featured = false,
                accent = 0xFF4361EE,
                posterUrl = pickPoster(images)
            )
        }
        return out
    }

    private fun pickPoster(images: JSONArray?): String? {
        if (images == null) return null
        val preferred = listOf("Poster", "BoxArt", "BrandedKeyArt", "TitledHeroArt", "SuperHeroArt")
        fun normalize(raw: String): String? {
            if (raw.isBlank()) return null
            return if (raw.startsWith("//")) "https:$raw" else raw
        }
        for (purpose in preferred) {
            for (i in 0 until images.length()) {
                val img = images.optJSONObject(i) ?: continue
                if (img.optString("ImagePurpose") == purpose) {
                    normalize(img.optString("Uri"))?.let { return it }
                }
            }
        }
        return normalize(images.optJSONObject(0)?.optString("Uri").orEmpty())
    }

    private fun slugify(title: String): String {
        val out = StringBuilder()
        var dash = false
        for (ch in title.lowercase()) {
            if (ch.isLetterOrDigit()) {
                out.append(ch)
                dash = false
            } else if (!dash) {
                out.append('-')
                dash = true
            }
        }
        return out.trim('-').toString()
    }

    private fun shortenGenre(raw: String): String {
        val value = raw.lowercase()
        return when {
            "race" in value -> "Racing"
            "shoot" in value -> "Shooter"
            "rpg" in value || "role" in value -> "RPG"
            "platform" in value -> "Platformer"
            "sandbox" in value -> "Sandbox"
            "surviv" in value -> "Survival"
            "sport" in value -> "Sports"
            "fight" in value -> "Fighting"
            "sim" in value -> "Simulation"
            "strat" in value -> "Strategy"
            "puzzle" in value -> "Puzzle"
            "adventure" in value -> "Adventure"
            "action" in value -> "Action"
            else -> raw
        }
    }

    private fun cacheFile(context: Context) = File(context.cacheDir, CACHE)

    private fun saveCache(context: Context, games: List<CatalogGame>) {
        val arr = JSONArray()
        games.forEach { game ->
            arr.put(
                JSONObject()
                    .put("id", game.id)
                    .put("slug", game.slug)
                    .put("title", game.title)
                    .put("tagline", game.tagline)
                    .put("genre", game.genre)
                    .put("poster", game.posterUrl.orEmpty())
            )
        }
        cacheFile(context).writeText(arr.toString())
    }

    private fun loadCache(context: Context): List<CatalogGame>? {
        val file = cacheFile(context)
        if (!file.exists()) return null
        return try {
            val arr = JSONArray(file.readText())
            val seen = mutableSetOf<String>()
            val games = mutableListOf<CatalogGame>()
            for (i in 0 until arr.length()) {
                val row = arr.optJSONObject(i) ?: continue
                val id = row.optString("id")
                if (id.isBlank() || !seen.add(id.uppercase())) continue
                val poster = row.optString("poster").ifBlank { null }
                games += CatalogGame(
                    id = id,
                    slug = row.optString("slug").ifBlank { id.lowercase() },
                    title = row.optString("title").ifBlank { id },
                    tagline = row.optString("tagline"),
                    genre = row.optString("genre").ifBlank { "Cloud" },
                    posterUrl = poster
                )
            }
            games
        } catch (_: Exception) {
            null
        }
    }

    private fun httpGet(url: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 20000
        conn.setRequestProperty("Accept", "application/json")
        conn.inputStream.bufferedReader().use { return it.readText() }
    }
}
