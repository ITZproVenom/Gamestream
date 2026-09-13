package com.gamestream.app

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel

class SessionStore(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("gamestream", Context.MODE_PRIVATE)

    var isSignedIn by mutableStateOf(prefs.getBoolean(KEY_SIGNED_IN, false))
        private set

    var accountLabel by mutableStateOf(prefs.getString(KEY_ACCOUNT, null))
        private set

    var webUrl by mutableStateOf(HOME_URL)
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

    var favoriteIds by mutableStateOf(prefs.getStringSet(KEY_FAVS, emptySet())?.toSet() ?: emptySet())
        private set
    var recentIds by mutableStateOf(prefs.getString("recent_ids", "")?.split(",")?.filter { it.isNotBlank() } ?: emptyList())
        private set

    var streamResolution by mutableStateOf(prefs.getString(KEY_RES, "Auto") ?: "Auto")
        private set

    var serverRegion by mutableStateOf(prefs.getString(KEY_REGION, "Auto") ?: "Auto")
        private set

    fun clearPendingJs() { pendingJs = null }

    fun markSignedIn(label: String = "Xbox Account") {
        accountLabel = label
        isSignedIn = true
        prefs.edit().putBoolean(KEY_SIGNED_IN, true).putString(KEY_ACCOUNT, label).apply()
    }

    fun signOut() {
        isSignedIn = false
        accountLabel = null
        isStreaming = false
        showNativeHub = true
        webUrl = HOME_URL
        prefs.edit().putBoolean(KEY_SIGNED_IN, false).remove(KEY_ACCOUNT).apply()
        pendingJs = "try { localStorage.clear(); sessionStorage.clear(); location.href='$HOME_URL'; } catch(e){}"
        reloadNonce++
    }

    fun openHome() {
        webUrl = HOME_URL
        isStreaming = false
        showNativeHub = true
        requestedTab = "library"
    }

    fun openXboxCloud() {
        webUrl = HOME_URL
        isStreaming = false
        showNativeHub = false
        requestedTab = "library"
    }

    fun openGame(game: CatalogGame) {
        webUrl = game.catalogUrl
        isStreaming = false
        showNativeHub = false
        requestedTab = "library"
        rememberRecent(game.id)
    }

    fun playGame(game: CatalogGame) {
        webUrl = game.launchUrl
        isStreaming = false
        showNativeHub = false
        requestedTab = "library"
        rememberRecent(game.id)
    }

    fun returnToHub() {
        isStreaming = false
        showNativeHub = true
        requestedTab = "library"
    }

    fun isFavorite(id: String) = favoriteIds.contains(id)

    fun toggleFavorite(game: CatalogGame) {
        favoriteIds = if (favoriteIds.contains(game.id)) favoriteIds - game.id else setOf(game.id) + favoriteIds
        prefs.edit().putStringSet(KEY_FAVS, favoriteIds).apply()
    }

    fun rememberRecent(id: String) {
        recentIds = listOf(id) + recentIds.filter { it != id }
        if (recentIds.size > 12) recentIds = recentIds.take(12)
        prefs.edit().putString("recent_ids", recentIds.joinToString(",")).apply()
    }

    fun favoriteGames(): List<CatalogGame> =
        favoriteIds.mapNotNull { id -> GameCatalog.games.find { it.id == id } }

    fun recentGames(): List<CatalogGame> =
        recentIds.mapNotNull { id -> GameCatalog.games.find { it.id == id } }

    fun openSearch(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        val escaped = q.replace("\\", "\\\\").replace("'", "\\'").replace("\n", " ")
        webUrl = HOME_URL
        isStreaming = false
        showNativeHub = false
        pendingJs = """
            (function(){
              var q='$escaped';
              function findInput(){
                return document.querySelector('input[type="search"], input[placeholder*="Search" i], input[aria-label*="Search" i], input[name="q"]');
              }
              var input=findInput();
              if(!input){
                var btn=document.querySelector('button[aria-label*="Search" i], [role="search"] button, a[href*="search"]');
                if(btn){ try{ btn.click(); }catch(e){} }
              }
              setTimeout(function(){
                input=findInput();
                if(input){
                  input.focus();
                  try{
                    var proto=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');
                    if(proto&&proto.set) proto.set.call(input,q); else input.value=q;
                  }catch(e){ input.value=q; }
                  input.dispatchEvent(new Event('input',{bubbles:true}));
                  input.dispatchEvent(new Event('change',{bubbles:true}));
                  var form=input.closest('form');
                  if(form) form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));
                  else input.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,which:13,bubbles:true}));
                } else {
                  location.href='https://www.xbox.com/play?search='+encodeURIComponent(q);
                }
              },280);
            })();
        """.trimIndent()
        requestedTab = "library"
    }

    fun reloadCurrent() {
        reloadNonce++
        pendingJs = "try { location.reload(); } catch(e){}"
    }

    fun updateStreamingFromUrl(url: String) {
        val streaming = isStreamingUrl(url)
        if (isStreaming != streaming) isStreaming = streaming
        if (streaming) showNativeHub = false
    }

    fun applyResolution(option: String) {
        streamResolution = option
        prefs.edit().putString(KEY_RES, option).apply()
        val mapped = when (option) {
            "720p" -> "720p"
            "1080p" -> "1080p"
            "1080p HQ" -> "1080p-hq"
            else -> "auto"
        }
        applyBxPref("stream.video.resolution", mapped)
    }

    fun applyRegion(option: String) {
        serverRegion = option
        prefs.edit().putString(KEY_REGION, option).apply()
        val mapped = when (option) {
            "North America" -> "us"
            "Europe" -> "eu"
            "Asia" -> "jp"
            "Australia" -> "au"
            else -> ""
        }
        applyBxPref("server.region", mapped)
    }

    fun refreshBetterXCloud() {
        bxRefreshToken++
        pendingJs = "try { location.reload(); } catch(e){}"
        requestedTab = "library"
    }

    private fun applyBxPref(key: String, value: String) {
        val ek = key.replace("\\", "\\\\").replace("'", "\\'")
        val ev = value.replace("\\", "\\\\").replace("'", "\\'")
        pendingJs = """
            (function(){
              try {
                var k='BetterXcloud';
                var d={};
                try { d=JSON.parse(localStorage.getItem(k)||'{}')||{}; } catch(e){}
                d['$ek']='$ev';
                localStorage.setItem(k, JSON.stringify(d));
                try { localStorage.setItem('BetterXcloud.$ek','$ev'); } catch(e){}
                setTimeout(function(){ location.reload(); }, 120);
              } catch(e){}
            })();
        """.trimIndent()
        requestedTab = "library"
        isStreaming = false
        showNativeHub = false
        if (!webUrl.contains("xbox.com/play")) webUrl = HOME_URL
    }

    companion object {
        const val HOME_URL = "https://www.xbox.com/play"
        private const val KEY_SIGNED_IN = "signed_in"
        private const val KEY_ACCOUNT = "account"
        private const val KEY_RES = "resolution"
        private const val KEY_REGION = "region"
        private const val KEY_FAVS = "favorite_ids"

        fun isStreamingUrl(url: String): Boolean {
            val lower = url.lowercase()
            if (lower.contains("/play/games")) return false
            return lower.contains("/play/launch") ||
                lower.contains("/launch/") ||
                lower.contains("/launch?") ||
                lower.contains("/stream/") ||
                lower.contains("/streaming")
        }
    }
}
