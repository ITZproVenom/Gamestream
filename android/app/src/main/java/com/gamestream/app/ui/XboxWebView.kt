package com.gamestream.app.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.gamestream.app.BetterXCloudInjector
import com.gamestream.app.ControllerRumble
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
    val rumble = remember { ControllerRumble.get(context) }

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
            settings.userAgentString =
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    url?.let { session.updateStreamingFromUrl(it) }
                    inject(view, session)
                    view?.evaluateJavascript(RUMBLE_BRIDGE, null)
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    url?.let { session.updateStreamingFromUrl(it) }
                    inject(view, session)
                    view?.evaluateJavascript(SPA_BRIDGE, null)
                    view?.evaluateJavascript(RUMBLE_BRIDGE, null)
                    CookieManager.getInstance().flush()
                }
            }

            addJavascriptInterface(object {
                @JavascriptInterface
                fun onUrl(href: String) {
                    mainHandler.post { session.updateStreamingFromUrl(href) }
                }

                @JavascriptInterface
                fun onRumble(weak: Float, strong: Float, durationMs: Float) {
                    mainHandler.post {
                        rumble.play(weak, strong, durationMs.toLong().coerceIn(40L, 2500L))
                    }
                }
            }, "GameStreamBridge")

            loadUrl(session.webUrl)
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            rumble.stop()
            webView.stopLoading()
            webView.onPause()
            webView.removeJavascriptInterface("GameStreamBridge")
            webView.webChromeClient = null
            webView.webViewClient = null
            webView.destroy()
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

private fun inject(view: WebView?, session: SessionStore) {
    if (view == null) return
    view.evaluateJavascript(BetterXCloudInjector.bootstrapAndModernCss(), null)
    view.evaluateJavascript(session.betterXCloudPrefsJs(reloadIfXbox = false), null)
    view.evaluateJavascript(RUMBLE_BRIDGE, null)
    val script = BetterXCloudInjector.currentScript(view.context) ?: return
    view.evaluateJavascript(
        "(function(){ if (window.__gsBxScript) return true; window.__gsBxScript = true; return false; })();",
        { already ->
            if (already != "true") {
                view.evaluateJavascript(script, null)
            }
        }
    )
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

private val SPA_BRIDGE = """
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

/**
 * xCloud only calls playEffect when vibrationActuator exists.
 * Android WebView often has no actuator → polyfill one that posts to native.
 */
private val RUMBLE_BRIDGE = """
(function(){
  function postRumble(weak, strong, duration) {
    try {
      var w = Number(weak) || 0;
      var s = Number(strong) || 0;
      var d = Number(duration) || 80;
      if (w < 0) w = 0; if (w > 1) w = 1;
      if (s < 0) s = 0; if (s > 1) s = 1;
      if (d < 0) d = 0; if (d > 2500) d = 2500;
      if (w < 0.01 && s < 0.01) return;
      if (window.GameStreamBridge && window.GameStreamBridge.onRumble) {
        window.GameStreamBridge.onRumble(w, s, d);
      }
    } catch (e) {}
  }
  window.__gsNativeRumble = postRumble;

  function makePolyActuator() {
    return {
      __gsPoly: true,
      __gsWrapped: true,
      playEffect: function(type, params) {
        try {
          params = params || {};
          var weak = params.weakMagnitude != null ? params.weakMagnitude : (params.magnitude || 0);
          var strong = params.strongMagnitude != null ? params.strongMagnitude : (params.magnitude || 0);
          var start = params.startDelay || 0;
          var duration = params.duration || 100;
          setTimeout(function(){ postRumble(weak, strong, duration); }, start);
        } catch (e) {}
        return Promise.resolve({ playEffect: 'complete' });
      },
      pulse: function(value, duration) {
        try { postRumble(value, value, duration || 100); } catch (e) {}
        return Promise.resolve(true);
      },
      reset: function() { return Promise.resolve(); }
    };
  }

  function wrapActuator(actuator) {
    if (!actuator || actuator.__gsWrapped) return actuator;
    try {
      if (typeof actuator.playEffect === 'function') {
        var original = actuator.playEffect.bind(actuator);
        actuator.playEffect = function(type, params) {
          try {
            params = params || {};
            var weak = params.weakMagnitude != null ? params.weakMagnitude : (params.magnitude || 0);
            var strong = params.strongMagnitude != null ? params.strongMagnitude : (params.magnitude || 0);
            var start = params.startDelay || 0;
            var duration = params.duration || 100;
            setTimeout(function(){ postRumble(weak, strong, duration); }, start);
          } catch (e) {}
          try { return original(type, params); } catch (e2) {
            return Promise.resolve({ playEffect: 'complete' });
          }
        };
      }
      if (typeof actuator.pulse === 'function') {
        var origPulse = actuator.pulse.bind(actuator);
        actuator.pulse = function(value, duration) {
          try { postRumble(value, value, duration || 100); } catch (e) {}
          try { return origPulse(value, duration); } catch (e2) { return Promise.resolve(true); }
        };
      }
      actuator.__gsWrapped = true;
    } catch (e) {}
    return actuator;
  }

  function ensurePad(p) {
    if (!p) return;
    try {
      if (p.vibrationActuator) {
        wrapActuator(p.vibrationActuator);
      } else {
        var poly = makePolyActuator();
        try {
          Object.defineProperty(p, 'vibrationActuator', { value: poly, configurable: true, writable: true });
        } catch (e1) {
          try { p.vibrationActuator = poly; } catch (e2) {}
        }
      }
      if (p.hapticActuators && p.hapticActuators.length) {
        for (var j = 0; j < p.hapticActuators.length; j++) wrapActuator(p.hapticActuators[j]);
      } else {
        var list = [p.vibrationActuator || makePolyActuator()];
        try {
          Object.defineProperty(p, 'hapticActuators', { value: list, configurable: true, writable: true });
        } catch (e3) {
          try { p.hapticActuators = list; } catch (e4) {}
        }
      }
    } catch (e) {}
  }

  function scanGamepads() {
    try {
      var pads = navigator.getGamepads ? navigator.getGamepads() : [];
      for (var i = 0; i < pads.length; i++) ensurePad(pads[i]);
    } catch (e) {}
  }

  if (!window.__gsRumbleBridge) {
    window.__gsRumbleBridge = true;
    try {
      var originalGet = navigator.getGamepads && navigator.getGamepads.bind(navigator);
      if (originalGet) {
        navigator.getGamepads = function() {
          var pads = originalGet();
          try {
            for (var i = 0; i < pads.length; i++) ensurePad(pads[i]);
          } catch (e) {}
          return pads;
        };
      }
    } catch (e) {}
    window.addEventListener('gamepadconnected', function(){ setTimeout(scanGamepads, 50); });
    try {
      var _pulse = window.navigator && window.navigator.vibrate;
      if (typeof _pulse === 'function') {
        window.navigator.vibrate = function(pattern) {
          try {
            var ms = 80, mag = 0.65;
            if (typeof pattern === 'number') ms = pattern;
            else if (pattern && pattern.length) ms = pattern[0] || 80;
            postRumble(mag * 0.7, mag, ms);
          } catch (e) {}
          try { return _pulse.apply(this, arguments); } catch (e2) { return false; }
        };
      } else {
        try {
          window.navigator.vibrate = function(pattern) {
            try {
              var ms = 80, mag = 0.65;
              if (typeof pattern === 'number') ms = pattern;
              else if (pattern && pattern.length) ms = pattern[0] || 80;
              postRumble(mag * 0.7, mag, ms);
            } catch (e) {}
            return true;
          };
        } catch (e) {}
      }
    } catch (e) {}
    setInterval(scanGamepads, 1000);
  }
  scanGamepads();
})();
""".trimIndent()
