package com.gamestream.app

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

object BetterXCloudInjector {
    private const val SCRIPT_URL =
        "https://github.com/redphx/better-xcloud/releases/latest/download/better-xcloud.user.js"
    private const val PREFS = "bx_cache"
    private const val KEY_SCRIPT = "script_v2"
    private const val KEY_DATE = "script_date_v2"

    @Volatile
    private var cached: String? = null

    fun bootstrapAndModernCss(): String = """
        (function(){
          if(!window.__bxInjected){
            window.__bxInjected=true;
            window.BetterXcloud=window.BetterXcloud||{injectedBy:'GameStreamAndroid'};
          }
          var CSS_ID='gamestream-bx-modern-v3';
          var css=`
            [class*="bx-"],[id*="bx-"],.bx-settings,.bx-dialog,.bx-stats-bar{
              font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif!important;
              color:#f5f5f7!important;
            }
            .bx-settings,.bx-dialog,[class*="bx-modal"],[class*="bx-panel"],[class*="bx-settings"]{
              background:rgba(16,16,18,.92)!important;
              backdrop-filter:blur(40px) saturate(180%)!important;
              border:1px solid rgba(255,255,255,.1)!important;
              border-radius:18px!important;
              box-shadow:0 20px 60px rgba(0,0,0,.55)!important;
              padding:16px!important;
            }
            [class*="bx-"] button{
              border-radius:12px!important;font-weight:600!important;
              background:rgba(255,255,255,.08)!important;color:#f5f5f7!important;
              border:1px solid rgba(255,255,255,.08)!important;padding:8px 14px!important;
            }
            .bx-stats-bar,[class*="bx-stats"]{
              background:rgba(10,10,12,.78)!important;
              backdrop-filter:blur(28px)!important;
              border-radius:16px!important;padding:8px 12px!important;
              font-size:11px!important;font-weight:600!important;
              display:flex!important;flex-wrap:wrap!important;gap:6px!important;
            }
            .bx-stats-bar>*,[class*="bx-stats"]>*{
              background:rgba(255,255,255,.07)!important;border-radius:8px!important;padding:3px 8px!important;
            }
          `;
          function apply(){
            var s=document.getElementById(CSS_ID);
            if(!s){s=document.createElement('style');s.id=CSS_ID;
              (document.head||document.documentElement).appendChild(s);}
            if(s.textContent!==css)s.textContent=css;
          }
          apply();
          try{new MutationObserver(apply).observe(document.documentElement,{childList:true,subtree:true});}catch(e){}
          setInterval(apply,2000);
        })();
    """.trimIndent()

    fun currentScript(context: Context): String? {
        cached?.let { return it }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val s = prefs.getString(KEY_SCRIPT, null)
        if (!s.isNullOrEmpty()) {
            cached = stripHeader(s)
            return cached
        }
        return null
    }

    fun invalidate(context: Context) {
        cached = null
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(KEY_SCRIPT).remove(KEY_DATE).apply()
    }

    suspend fun ensureFetched(context: Context): String? = withContext(Dispatchers.IO) {
        currentScript(context)?.let { return@withContext it }
        try {
            val conn = (URL(SCRIPT_URL).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 20000
                requestMethod = "GET"
                instanceFollowRedirects = true
            }
            if (conn.responseCode !in 200..299) return@withContext null
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            if (body.length < 1000) return@withContext null
            val cleaned = stripHeader(body)
            cached = cleaned
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_SCRIPT, cleaned)
                .putLong(KEY_DATE, System.currentTimeMillis())
                .apply()
            cleaned
        } catch (_: Exception) {
            null
        }
    }

    private fun stripHeader(source: String): String {
        val marker = "// ==/UserScript=="
        val idx = source.indexOf(marker)
        return if (idx >= 0) source.substring(idx + marker.length).trim() else source
    }
}
