package com.gamestream.app.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
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
    val webView = remember {
        WebView(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(AndroidColor.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    val boot = BetterXCloudInjector.bootstrapAndModernCss()
                    view?.evaluateJavascript(boot, null)
                    BetterXCloudInjector.currentScript(context)?.let {
                        view?.evaluateJavascript(it, null)
                    }
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    url?.let { session.updateStreamingFromUrl(it) }
                    val boot = BetterXCloudInjector.bootstrapAndModernCss()
                    view?.evaluateJavascript(boot, null)
                    BetterXCloudInjector.currentScript(context)?.let {
                        view?.evaluateJavascript(it, null)
                    }
                    view?.evaluateJavascript(
                        """
                        (function(){
                          try {
                            var href=location.href||'';
                            if(window.GameStreamBridge) window.GameStreamBridge.onUrl(href);
                          } catch(e){}
                        })();
                        """.trimIndent(),
                        null
                    )
                }
            }

            addJavascriptInterface(object {
                @android.webkit.JavascriptInterface
                fun onUrl(href: String) {
                    session.updateStreamingFromUrl(href)
                }
            }, "GameStreamBridge")

            loadUrl(session.webUrl)
        }
    }

    LaunchedEffect(session.webUrl) {
        if (webView.url != session.webUrl) {
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
