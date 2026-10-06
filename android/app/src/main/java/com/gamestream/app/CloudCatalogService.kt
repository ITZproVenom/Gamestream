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
    private const val SIGL_ID = "29a81209-df6f-41fd-a528-2ae6b91f719c"
    private const val CACHE = "xcloud-catalog-v2.json"

    /// The cache is read once per process; the flag is not reused as a lock
    /// for the network fetch, which has its own.
    @Volatile private var cacheInstalled = false
    @Volatile private var fetching = false

    /// The device's own market and language, so a player outside the United
    /// States sees their own catalogue in their own language. Asking for the
    /// US list everywhere meant titles their region cannot stream at all,
    /// which fail on the launch page with no explanation.
    private fun market(): String {
        val region = java.util.Locale.getDefault().country.uppercase()
        return if (region.length == 2) region else "US"
    }

    private fun language(): String {
        val locale = java.util.Locale.getDefault()
        val language = locale.language.lowercase().ifBlank { "en" }
        val region = locale.country.lowercase()
        return if (region.length == 2) "$language-$region" else language
    }

    private fun siglUrl(market: String, language: String): String =
        "https://catalog.gamepass.com/sigls/v2?id=$SIGL_ID&language=$language&market=$market"

    fun refreshIfNeeded(context: Context) {
        if (cacheInstalled) return
        cacheInstalled = true
        loadCache(context)?.takeIf { it.size >= 20 }?.let { GameCatalog.installLiveCatalog(it) }
    }

    suspend fun fetchAndInstall(context: Context) = withContext(Dispatchers.IO) {
        refreshIfNeeded(context)
        if (fetching) return@withContext
        fetching = true
        try {
            val remote = fetchRemoteProgressive(context)
            if (remote.size >= 20) {
                saveCache(context, remote)
                withContext(Dispatchers.Main) {
                    GameCatalog.installLiveCatalog(remote)
                }
            }
        } catch (_: Exception) {
        } finally {
            fetching = false
        }
    }

    private suspend fun fetchRemoteProgressive(context: Context): List<CatalogGame> {
        val market = market()
        var raw = JSONArray(httpGet(siglUrl(market, language())))
        if (raw.length() == 0 && market != "US") {
            // A market with nothing behind it falls back to the US list
            // rather than leaving the catalogue empty.
            raw = JSONArray(httpGet(siglUrl("US", "en-us")))
        }
        val ids = linkedSetOf<String>()
        for (i in 0 until raw.length()) {
            val row = raw.optJSONObject(i) ?: continue
            val id = row.optString("id").trim()
            if (id.isNotEmpty()) ids.add(id)
        }
        val games = mutableListOf<CatalogGame>()
        val list = ids.toList()
        var index = 0
        var published = false
        var failedPages = 0
        var pages = 0
        while (index < list.size) {
            val slice = list.subList(index, minOf(index + 20, list.size)).toList()
            index += 20
            pages += 1
            try {
                games += hydrate(slice)
            } catch (_: Exception) {
                failedPages += 1
            }
            if (!published && games.size >= 24) {
                val snapshot = games.distinctBy { it.id.uppercase() }
                withContext(Dispatchers.Main) {
                    GameCatalog.installLiveCatalog(snapshot)
                }
                published = true
            }
        }
        var merged = games.distinctBy { it.id.uppercase() }
        if (failedPages > 0 && pages > 0) {
            // A page that failed must not quietly delete the games it would
            // have carried. Anything still on the playable list but missing
            // from this pass is kept from what is already on screen, which is
            // better information than nothing.
            val playable = list.map { it.uppercase() }.toSet()
            val present = merged.map { it.id.uppercase() }.toSet()
            val retained = GameCatalog.games.filter {
                val key = it.id.uppercase()
                key in playable && key !in present
            }
            if (retained.isNotEmpty()) merged = merged + retained
        }
        return merged
    }

    private fun hydrate(ids: List<String>): List<CatalogGame> {
        val joined = ids.joinToString(",")
        val url =
            "https://displaycatalog.mp.microsoft.com/v7.0/products" +
                "?bigIds=$joined&market=${market()}&languages=${language()}&MS-CV=GS.1"
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

    fun clearCache(context: Context) {
        cacheInstalled = false
        runCatching { cacheFile(context).delete() }
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
        return try {
            conn.connectTimeout = 15000
            conn.readTimeout = 20000
            conn.requestMethod = "GET"
            conn.setRequestProperty("Accept", "application/json")
            val status = conn.responseCode
            if (status !in 200..299) {
                throw java.io.IOException("HTTP $status")
            }
            conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }
}
