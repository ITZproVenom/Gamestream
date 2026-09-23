package com.gamestream.app

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class SessionStore(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("gamestream", Context.MODE_PRIVATE)
    private val playActivity = PlayActivity.get(app)
    private var didConsumeLaunchResume = false

    var isSignedIn by mutableStateOf(false)
        private set
    var accountLabel by mutableStateOf(prefs.getString(KEY_ACCOUNT, null))
        private set
    var webUrl by mutableStateOf(IDLE_URL)
        private set
    var isStreaming by mutableStateOf(false)
        private set
    var requestedTab by mutableStateOf<String?>(null)
    var pendingJs by mutableStateOf<String?>(null)
    var reloadNonce by mutableIntStateOf(0)
        private set
    var bxRefreshToken by mutableIntStateOf(0)
        private set
    var showNativeHub by mutableStateOf(true)
    var offerPlayNext by mutableStateOf(false)
    var resumeLastOnOpen by mutableStateOf(prefs.getBoolean(KEY_RESUME, false))
        private set
    var favoriteIds by mutableStateOf(prefs.getStringSet(KEY_FAVS, emptySet())?.toSet() ?: emptySet())
        private set
    var recentIds by mutableStateOf(prefs.getString("recent_ids", "")?.split(",")?.filter { it.isNotBlank() } ?: emptyList())
        private set
    var queueIds by mutableStateOf(prefs.getString("queue_ids", "")?.split(",")?.filter { it.isNotBlank() } ?: emptyList())
        private set
    var streamResolution by mutableStateOf(prefs.getString(KEY_RES, "Auto") ?: "Auto")
        private set
    var serverRegion by mutableStateOf(prefs.getString(KEY_REGION, "Auto") ?: "Auto")
        private set
    var searchQuery by mutableStateOf("")

    init {
        val proof = prefs.getInt(KEY_AUTH_PROOF, 0)
        val stored = prefs.getBoolean(KEY_SIGNED_IN, false)
        if (stored && proof == AUTH_PROOF_VERSION) {
            isSignedIn = true
            accountLabel = prefs.getString(KEY_ACCOUNT, null)
        } else if (stored) {
            prefs.edit().putBoolean(KEY_SIGNED_IN, false).remove(KEY_ACCOUNT).remove(KEY_AUTH_PROOF).apply()
            accountLabel = null
        }
    }

    fun activity(): PlayActivity = playActivity
    fun clearPendingJs() { pendingJs = null }
    fun updateResumeLastOnOpen(enabled: Boolean) {
        resumeLastOnOpen = enabled
        prefs.edit().putBoolean(KEY_RESUME, enabled).apply()
    }

    fun markSignedInAfterMicrosoftAuth(label: String = "Xbox Account") {
        accountLabel = label
        isSignedIn = true
        prefs.edit().putBoolean(KEY_SIGNED_IN, true).putString(KEY_ACCOUNT, label).putInt(KEY_AUTH_PROOF, AUTH_PROOF_VERSION).apply()
    }

    fun signOut() {
        playActivity.end()
        isSignedIn = false
        accountLabel = null
        isStreaming = false
        offerPlayNext = false
        showNativeHub = true
        webUrl = IDLE_URL
        prefs.edit().putBoolean(KEY_SIGNED_IN, false).remove(KEY_ACCOUNT).remove(KEY_AUTH_PROOF).apply()
        pendingJs = null
    }

    fun openHome() { returnToHub() }
    fun openXboxCloud() { returnToHub() }
    fun openGame(game: CatalogGame) {
        webUrl = IDLE_URL
        isStreaming = false
        offerPlayNext = false
        showNativeHub = true
        requestedTab = "library"
        rememberRecent(game.id)
    }
    fun playGame(game: CatalogGame) {
        pendingJs = null
        webUrl = game.launchUrl
        isStreaming = true
        offerPlayNext = false
        showNativeHub = false
        requestedTab = "library"
        rememberRecent(game.id)
    }
    fun resumeLastStream(): Boolean {
        val game = recentGames().firstOrNull() ?: return false
        playGame(game)
        return true
    }
    fun consumeLaunchResumeIfNeeded() {
        if (didConsumeLaunchResume) return
        didConsumeLaunchResume = true
        if (!resumeLastOnOpen || !isSignedIn || isStreaming) return
        resumeLastStream()
    }
    fun returnToHub() {
        playActivity.end()
        isStreaming = false
        webUrl = IDLE_URL
        showNativeHub = true
        requestedTab = "library"
    }
    fun exitStreamToHub() {
        playActivity.end()
        offerPlayNext = queuedGames().isNotEmpty()
        webUrl = IDLE_URL
        isStreaming = false
        showNativeHub = true
        requestedTab = "library"
    }
    fun playNextFromStream() {
        playActivity.end()
        offerPlayNext = false
        if (!playNextQueued()) exitStreamToHub()
    }
    fun isFavorite(id: String) = favoriteIds.contains(id)
    fun toggleFavorite(game: CatalogGame) {
        favoriteIds = if (favoriteIds.contains(game.id)) favoriteIds - game.id else setOf(game.id) + favoriteIds
        prefs.edit().putStringSet(KEY_FAVS, favoriteIds).apply()
    }
    fun rememberRecent(id: String) {
        recentIds = listOf(id) + recentIds.filter { it != id }
        if (recentIds.size > 24) recentIds = recentIds.take(24)
        prefs.edit().putString("recent_ids", recentIds.joinToString(",")).apply()
    }
    fun isQueued(id: String) = queueIds.contains(id)
    fun toggleQueue(game: CatalogGame) {
        queueIds = if (queueIds.contains(game.id)) queueIds.filter { it != game.id } else (queueIds + game.id).take(16)
        prefs.edit().putString("queue_ids", queueIds.joinToString(",")).apply()
    }
    fun dequeue(id: String) {
        queueIds = queueIds.filter { it != id }
        prefs.edit().putString("queue_ids", queueIds.joinToString(",")).apply()
    }
    fun queuedGames(): List<CatalogGame> = queueIds.mapNotNull { id -> GameCatalog.games.find { it.id == id } }
    fun playNextQueued(): Boolean {
        val next = queuedGames().firstOrNull() ?: return false
        dequeue(next.id)
        playGame(next)
        return true
    }
    fun favoriteGames(): List<CatalogGame> = favoriteIds.mapNotNull { id -> GameCatalog.games.find { it.id == id } }
    fun recentGames(): List<CatalogGame> = recentIds.mapNotNull { id -> GameCatalog.games.find { it.id == id } }

    /** Open Xbox Cloud search in the stream WebView so results are live catalog. */
    fun openSearch(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        searchQuery = q
        val encoded = URLEncoder.encode(q, StandardCharsets.UTF_8.toString())
        pendingJs = null
        webUrl = "https://www.xbox.com/play/search/$encoded"
        isStreaming = true
        offerPlayNext = false
        showNativeHub = false
        requestedTab = "library"
    }

    fun reloadCurrent() { reloadNonce++; pendingJs = "try { location.reload(); } catch(e){}" }

    fun updateStreamingFromUrl(url: String) {
        val streaming = isStreamingUrl(url)
        val isSearch = url.lowercase().contains("/play/search")
        // Stay in player for cloud search pages
        if (isStreaming && !streaming && !isSearch) {
            offerPlayNext = queuedGames().isNotEmpty()
            playActivity.end()
        }
        if (isStreaming != streaming && !isSearch) isStreaming = streaming
        if (streaming || isSearch) {
            if (!isStreaming) isStreaming = true
            showNativeHub = false
            offerPlayNext = false
            if (streaming) recentGames().firstOrNull()?.let { playActivity.begin(it.id, it.title) }
        }
    }

    fun applyResolution(option: String) {
        streamResolution = option
        prefs.edit().putString(KEY_RES, option).apply()
        val mapped = when (option) { "720p" -> "720p"; "1080p" -> "1080p"; "1080p HQ" -> "1080p-hq"; else -> "auto" }
        applyBxPref("stream.video.resolution", mapped)
    }
    fun applyRegion(option: String) {
        serverRegion = option
        prefs.edit().putString(KEY_REGION, option).apply()
        val mapped = when (option) {
            "North America" -> "us"; "Europe" -> "eu"; "Asia" -> "jp"; "Australia" -> "au"; else -> ""
        }
        applyBxPref("server.region", mapped)
    }
    fun refreshBetterXCloud() {
        bxRefreshToken++
        if (isStreaming && webUrl.contains("xbox.com")) {
            pendingJs = "try { location.reload(); } catch(e){}"
        }
    }

    fun betterXCloudPrefsJs(reloadIfXbox: Boolean): String {
        val map = storedBxPrefs()
        val assignments = map.entries.joinToString("\n") { (k, v) ->
            val ek = k.replace("\\", "\\\\").replace("'", "\\'")
            val ev = v.replace("\\", "\\\\").replace("'", "\\'")
            "data['$ek']='$ev'; try { localStorage.setItem('BetterXcloud.$ek','$ev'); } catch(e){}"
        }
        val reload = if (reloadIfXbox) "if (/xbox\\.com/i.test(location.host)) { setTimeout(function(){ location.reload(); }, 80); }" else ""
        return """
            (function(){
              try {
                if (!location.host || location.host.indexOf('xbox.com') === -1) return;
                var k='BetterXcloud';
                var d={};
                try { d=JSON.parse(localStorage.getItem(k)||'{}')||{}; } catch(e){}
                var data=d;
                $assignments
                localStorage.setItem(k, JSON.stringify(data));
                $reload
              } catch(e){}
            })();
        """.trimIndent()
    }

    private fun storedBxPrefs(): Map<String, String> {
        val raw = prefs.getString(KEY_BX_PREFS, "") ?: ""
        if (raw.isBlank()) return emptyMap()
        return raw.split('|').mapNotNull { part ->
            val idx = part.indexOf('=')
            if (idx <= 0) null else part.substring(0, idx) to part.substring(idx + 1)
        }.toMap()
    }

    private fun persistBxPrefs(map: Map<String, String>) {
        val raw = map.entries.joinToString("|") { "${it.key}=${it.value}" }
        prefs.edit().putString(KEY_BX_PREFS, raw).apply()
    }

    private fun applyBxPref(key: String, value: String) {
        val map = storedBxPrefs().toMutableMap()
        map[key] = value
        persistBxPrefs(map)
        if (isStreaming && webUrl.contains("xbox.com")) {
            pendingJs = betterXCloudPrefsJs(reloadIfXbox = true)
        }
    }

    companion object {
        const val HOME_URL = "https://www.xbox.com/play"
        const val IDLE_URL = "about:blank"
        private const val KEY_SIGNED_IN = "signed_in"
        private const val KEY_ACCOUNT = "account"
        private const val KEY_AUTH_PROOF = "microsoft_auth_proof_v2"
        const val AUTH_PROOF_VERSION = 2
        private const val KEY_RES = "resolution"
        private const val KEY_REGION = "region"
        private const val KEY_FAVS = "favorite_ids"
        private const val KEY_RESUME = "resume_last_on_open"
        private const val KEY_BX_PREFS = "bx_prefs_v1"
        fun isStreamingUrl(url: String): Boolean {
            val lower = url.lowercase()
            if (lower.contains("/play/games")) return false
            if (lower.contains("/play/search")) return false
            return lower.contains("/play/launch") || lower.contains("/launch/") || lower.contains("/launch?") || lower.contains("/stream/") || lower.contains("/streaming")
        }
    }
}
