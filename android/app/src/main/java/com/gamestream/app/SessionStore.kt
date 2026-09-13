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

    var streamResolution by mutableStateOf(prefs.getString(KEY_RES, "Auto") ?: "Auto")
        private set

    var serverRegion by mutableStateOf(prefs.getString(KEY_REGION, "Auto") ?: "Auto")
        private set

    fun clearPendingJs() {
        pendingJs = null
    }

    fun markSignedIn(label: String = "Xbox Account") {
        accountLabel = label
        isSignedIn = true
        prefs.edit()
            .putBoolean(KEY_SIGNED_IN, true)
            .putString(KEY_ACCOUNT, label)
            .apply()
    }

    fun signOut() {
        isSignedIn = false
        accountLabel = null
        isStreaming = false
        webUrl = HOME_URL
        prefs.edit()
            .putBoolean(KEY_SIGNED_IN, false)
            .remove(KEY_ACCOUNT)
            .apply()
        pendingJs = "try { localStorage.clear(); sessionStorage.clear(); location.href='$HOME_URL'; } catch(e){}"
        reloadNonce++
    }

    fun openHome() {
        webUrl = HOME_URL
        isStreaming = false
        requestedTab = "library"
    }

    fun openSearch(query: String) {
        val encoded = java.net.URLEncoder.encode(query.trim(), "UTF-8")
        webUrl = "https://www.xbox.com/play/search?q=$encoded"
        isStreaming = false
        requestedTab = "library"
    }

    fun reloadCurrent() {
        reloadNonce++
        pendingJs = "try { location.reload(); } catch(e){}"
    }

    fun updateStreamingFromUrl(url: String) {
        val lower = url.lowercase()
        val streaming = lower.contains("/launch") ||
            lower.contains("/play/game") ||
            lower.contains("/play/launch") ||
            lower.contains("/stream")
        if (isStreaming != streaming) isStreaming = streaming
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
        if (!webUrl.contains("xbox.com/play")) webUrl = HOME_URL
    }

    companion object {
        const val HOME_URL = "https://www.xbox.com/play"
        private const val KEY_SIGNED_IN = "signed_in"
        private const val KEY_ACCOUNT = "account"
        private const val KEY_RES = "resolution"
        private const val KEY_REGION = "region"
    }
}
