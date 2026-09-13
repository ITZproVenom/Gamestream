package com.gamestream.app.ui.screens

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import coil.compose.AsyncImage
import com.gamestream.app.GameCatalog
import com.gamestream.app.OnboardingPrefs
import com.gamestream.app.SessionStore

@Composable
fun IntroScreen(onFinished: () -> Unit) {
    val context = LocalContext.current
    val motion = rememberInfiniteTransition(label = "intro")
    val shift by motion.animateFloat(initialValue = -18f, targetValue = 18f, animationSpec = infiniteRepeatable(tween(18000, easing = LinearEasing), RepeatMode.Reverse), label = "shift")
    val scale by motion.animateFloat(initialValue = 1f, targetValue = 1.08f, animationSpec = infiniteRepeatable(tween(20000), RepeatMode.Reverse), label = "scale")
    val posters = remember { GameCatalog.games.mapNotNull { it.posterUrl }.take(12) }
    fun finish() { OnboardingPrefs.markIntroDone(context); onFinished() }
    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black)) {
        val columns = if (maxWidth > 700.dp) 5 else 3
        Column(Modifier.fillMaxSize().scale(scale).offset(x = shift.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            repeat(4) { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    repeat(columns) { col ->
                        val index = (row * columns + col) % maxOf(posters.size, 1)
                        AsyncImage(model = posters.getOrNull(index), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.weight(1f).height(210.dp).clip(RoundedCornerShape(10.dp)).background(Color(0xFF1A1228)))
                    }
                }
            }
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0x33000000), Color(0x99000000), Color(0xF2000000)))))
        TextButton(onClick = { finish() }, modifier = Modifier.align(Alignment.TopStart).padding(12.dp)) { Text("Skip", color = Color.White, maxLines = 1) }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 24.dp, vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 520.dp).clip(RoundedCornerShape(28.dp)).background(Color(0xCC16161F)).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.SportsEsports, contentDescription = null, tint = Color(0xFFB9A8FF), modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(12.dp))
                Text("GameStream", color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(10.dp))
                Text("Xbox Cloud Gaming with Better xCloud and a native GameHub — play instantly.", color = Color(0xFFD0D0D8), textAlign = TextAlign.Center, fontSize = 15.sp)
            }
            Spacer(Modifier.height(20.dp))
            Button(onClick = { finish() }, modifier = Modifier.fillMaxWidth().widthIn(max = 520.dp).height(54.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6C5CE7))) {
                Text("Get Started", maxLines = 1)
            }
        }
    }
}

@Composable
fun WelcomeScreen(session: SessionStore) {
    var showLogin by remember { mutableStateOf(false) }
    if (showLogin) {
        MicrosoftSignInWeb(session = session, onClose = { showLogin = false })
        return
    }
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF12081F), Color(0xFF0A0A12))))) {
        Column(Modifier.fillMaxSize().padding(28.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.SportsEsports, contentDescription = null, tint = Color(0xFFB9A8FF), modifier = Modifier.size(52.dp))
            Spacer(Modifier.height(16.dp))
            Text("GameStream", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Spacer(Modifier.height(6.dp))
            Text("Welcome", color = Color(0xFFB0B0B8), fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Spacer(Modifier.height(12.dp))
            Text("Sign in with Microsoft to open GameHub, stream Xbox Cloud games, and use Better xCloud.", color = Color(0xFFB0B0B8), textAlign = TextAlign.Center)
            Spacer(Modifier.height(28.dp))
            Button(onClick = { showLogin = true }, modifier = Modifier.fillMaxWidth().widthIn(max = 520.dp).height(54.dp), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6C5CE7))) {
                Text("Sign in with Microsoft", maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.height(10.dp))
            Text("Uses Microsoft's real sign-in page. GameStream never stores your password.", color = Color(0xFF808088), textAlign = TextAlign.Center, fontSize = 12.sp)
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun MicrosoftSignInWeb(session: SessionStore, onClose: () -> Unit) {
    BackHandler { onClose() }
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().background(Color.Black)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onClose) { Text("Close", color = Color.White, maxLines = 1) }
            Text("Microsoft account", color = Color.White, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), textAlign = TextAlign.Center, maxLines = 1)
            Spacer(Modifier.width(64.dp))
        }
        AndroidView(
            factory = {
                WebView(context).apply {
                    setBackgroundColor(AndroidColor.BLACK)
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                    settings.userAgentString = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    webViewClient = object : WebViewClient() {
                        private var sawMicrosoftLogin = false
                        private var completing = false
                        override fun shouldOverrideUrlLoading(view: WebView?, request: android.webkit.WebResourceRequest?): Boolean {
                            request?.url?.toString()?.let { note(it) }
                            return false
                        }
                        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) { url?.let { note(it) } }
                        override fun onPageFinished(view: WebView?, url: String?) {
                            url?.let { note(it) }
                            val href = url.orEmpty()
                            if (!completing && sawMicrosoftLogin && isXboxDestination(href)) {
                                CookieManager.getInstance().flush()
                                if (cookiesIndicateMicrosoftAuth()) {
                                    completing = true
                                    session.markSignedInAfterMicrosoftAuth()
                                }
                            }
                            CookieManager.getInstance().flush()
                        }
                        private fun note(raw: String) {
                            val href = raw.lowercase()
                            if (href.contains("login.live.com") || href.contains("login.microsoftonline.com") || href.contains("login.microsoft.com") || href.contains("sisu.xboxlive.com")) {
                                sawMicrosoftLogin = true
                            }
                        }
                        private fun isXboxDestination(raw: String): Boolean {
                            val href = raw.lowercase()
                            if (href.contains("login.live.com") || href.contains("login.microsoft")) return false
                            return href.contains("xbox.com") || href.contains("xboxlive.com")
                        }
                        private fun cookiesIndicateMicrosoftAuth(): Boolean {
                            val raw = CookieManager.getInstance().getCookie("https://login.live.com").orEmpty() +
                                ";" + CookieManager.getInstance().getCookie("https://www.xbox.com").orEmpty() +
                                ";" + CookieManager.getInstance().getCookie("https://xboxlive.com").orEmpty()
                            val lower = raw.lowercase()
                            return listOf("mspauth", "mspprof", "rpssecauth", "xboxlive", "xbl").any { lower.contains(it) }
                        }
                    }
                    loadUrl("https://login.live.com/login.srf?wa=wsignin1.0&wp=MBI_SSL&wreply=https%3A%2F%2Fwww.xbox.com%2Fplay&lc=1033")
                }
            },
            modifier = Modifier.fillMaxSize()
        )
    }
}
