package com.gamestream.app.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.gamestream.app.BetterXCloudInjector
import com.gamestream.app.SessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun XboxWebView(
    session: SessionStore,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    val webView = remember {
        WebView(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(AndroidColor.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.setSupportMultipleWindows(false)
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            // Xbox Cloud Gaming expects a desktop Chromium session.
            settings.userAgentString =
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?
                ): Boolean {
                    val next = request?.url?.toString() ?: return false
                    if (next.startsWith("http://") || next.startsWith("https://")) {
                        view?.loadUrl(next)
                        return true
                    }
                    return false
                }

                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    url?.let { session.updateStreamingFromUrl(it) }
                    inject(view)
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    url?.let { session.updateStreamingFromUrl(it) }
                    inject(view)
                    view?.evaluateJavascript(SPA_BRIDGE, null)
                    CookieManager.getInstance().flush()
                }
            }

            addJavascriptInterface(object {
                @android.webkit.JavascriptInterface
                fun onUrl(href: String) {
                    mainHandler.post { session.updateStreamingFromUrl(href) }
                }
            }, "GameStreamBridge")

            loadUrl(session.webUrl)
        }
    }

    LaunchedEffect(session.webUrl) {
        val current = webView.url ?: ""
        if (!urlsEquivalent(current, session.webUrl)) {
            webView.loadUrl(session.webUrl)
        }
    }

    LaunchedEffect(session.reloadNonce) {
        if (session.reloadNonce > 0) webView.reload()
    }

    LaunchedEffect(session.pendingJs) {
        val js = session.pendingJs ?: return@LaunchedEffect
        webView.evaluateJavascript(js, null)
        session.clearPendingJs()
    }

    LaunchedEffect(session.bxRefreshToken) {
        if (session.bxRefreshToken > 0) {
            BetterXCloudInjector.invalidate(context)
            withContext(Dispatchers.IO) {
                BetterXCloudInjector.ensureFetched(context)
            }
            webView.reload()
        }
    }

    AndroidView(
        factory = { webView },
        modifier = modifier
    )
}

private fun inject(view: WebView?) {
    val boot = BetterXCloudInjector.bootstrapAndModernCss()
    view?.evaluateJavascript(boot, null)
    BetterXCloudInjector.currentScript(view?.context ?: return)?.let { script ->
        view.evaluateJavascript(
            """
            (function(){
              if (window.__gsBxScript) return;
              window.__gsBxScript = true;
              $script
            })();
            """.trimIndent(),
            null
        )
    }
}

private fun urlsEquivalent(a: String, b: String): Boolean {
    if (a == b) return true
    fun norm(raw: String): String =
        raw.lowercase()
            .removePrefix("https://")
            .removePrefix("http://")
            .removePrefix("www.")
            .trimEnd('/')
            .replace(Regex("/[a-z]{2}(-[a-z]{2})?/play"), "/play")
    return norm(a) == norm(b)
}

private const val SPA_BRIDGE = """
(function(){
  if (window.__gsSpaBridge) return;
  window.__gsSpaBridge = true;
  function notify(){
    try {
      var href = location.href || '';
      if (window.GameStreamBridge) window.GameStreamBridge.onUrl(href);
    } catch (e) {}
  }
  notify();
  var push = history.pushState;
  history.pushState = function(){
    push.apply(this, arguments);
    setTimeout(notify, 50);
  };
  var replace = history.replaceState;
  history.replaceState = function(){
    replace.apply(this, arguments);
    setTimeout(notify, 50);
  };
  window.addEventListener('popstate', function(){ setTimeout(notify, 50); });
  setInterval(notify, 1500);
})();
""".trimIndent()
