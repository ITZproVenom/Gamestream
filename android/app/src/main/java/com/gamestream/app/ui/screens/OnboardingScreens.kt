package com.gamestream.app.ui.screens

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Star
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.gamestream.app.OnboardingPrefs
import com.gamestream.app.SessionStore

@Composable
fun IntroScreen(onFinished: () -> Unit) {
    val context = LocalContext.current
    val pulse = rememberInfiniteTransition(label = "intro")
    val glow by pulse.animateFloat(
        initialValue = 0.86f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1800), RepeatMode.Reverse),
        label = "glow"
    )

    fun finish() {
        OnboardingPrefs.markIntroDone(context)
        onFinished()
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF12081F), Color(0xFF0A0A12), Color(0xFF050508))
                )
            )
    ) {
        TextButton(
            onClick = { finish() },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(12.dp)
        ) {
            Text("Skip", color = Color.White, maxLines = 1)
        }

        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.SpaceBetween,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(36.dp))

            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                PosterChip(Icons.Default.Star, "Instant play", -8f)
                PosterChip(Icons.Default.Cloud, "Xbox Cloud", 7f)
            }
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                PosterChip(Icons.Default.GridView, "GameHub", 5f)
                PosterChip(Icons.Default.SportsEsports, "Better xCloud", -6f)
            }

            Column(
                Modifier
                    .widthIn(max = 520.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(Color(0xCC16161F))
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    Icons.Default.SportsEsports,
                    contentDescription = null,
                    tint = Color(0xFFB9A8FF),
                    modifier = Modifier.size(48.dp).scale(glow)
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    "GameStream",
                    color = Color.White,
                    fontSize = 36.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    "Xbox Cloud Gaming, Better xCloud, and GameHub \u2014 one cinematic place to play.",
                    color = Color(0xFFD0D0D8),
                    textAlign = TextAlign.Center,
                    fontSize = 15.sp
                )
            }

            Button(
                onClick = { finish() },
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 520.dp)
                    .height(54.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6C5CE7))
            ) {
                Text("Get Started", maxLines = 1)
            }
        }
    }
}

@Composable
private fun PosterChip(icon: ImageVector, title: String, rot: Float) {
    Column(
        Modifier
            .rotate(rot)
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xAA1C1C28))
            .padding(horizontal = 14.dp, vertical = 18.dp)
            .widthIn(min = 110.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
        Spacer(Modifier.height(8.dp))
        Text(title, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

@Composable
fun WelcomeScreen(session: SessionStore) {
    var showLogin by remember { mutableStateOf(false) }

    if (showLogin) {
        MicrosoftSignInWeb(session = session, onClose = { showLogin = false })
        return
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(listOf(Color(0xFF12081F), Color(0xFF0A0A12)))
            )
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(28.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(Icons.Default.SportsEsports, contentDescription = null, tint = Color(0xFFB9A8FF), modifier = Modifier.size(52.dp))
            Spacer(Modifier.height(16.dp))
            Text("GameStream", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Spacer(Modifier.height(6.dp))
            Text("Welcome", color = Color(0xFFB0B0B8), fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Spacer(Modifier.height(12.dp))
            Text(
                "Sign in with Microsoft to open GameHub, stream Xbox Cloud games, and use Better xCloud.",
                color = Color(0xFFB0B0B8),
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(28.dp))
            Button(
                onClick = { showLogin = true },
                modifier = Modifier.fillMaxWidth().height(54.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6C5CE7))
            ) {
                Text("Sign in with Microsoft", maxLines = 1)
            }
            Spacer(Modifier.height(10.dp))
            Text(
                "Uses Microsoft's real sign-in page. GameStream never stores your password.",
                color = Color(0xFF808088),
                textAlign = TextAlign.Center,
                fontSize = 12.sp
            )
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun MicrosoftSignInWeb(session: SessionStore, onClose: () -> Unit) {
    BackHandler { onClose() }
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().background(Color.Black)) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onClose) { Text("Close", color = Color.White, maxLines = 1) }
            Text(
                "Microsoft account",
                color = Color.White,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.Center,
                maxLines = 1
            )
            Spacer(Modifier.size(64.dp))
        }
        AndroidView(
            factory = {
                WebView(context).apply {
                    setBackgroundColor(AndroidColor.BLACK)
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                    settings.userAgentString =
                        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                            "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView?, url: String?) {
                            val href = url?.lowercase().orEmpty()
                            val onXboxPlay = href.contains("xbox.com") && href.contains("/play")
                            val onLogin = href.contains("login.live.com") || href.contains("login.microsoftonline.com")
                            if (onXboxPlay && !onLogin) {
                                session.markSignedIn()
                            }
                            CookieManager.getInstance().flush()
                        }
                    }
                    loadUrl("https://www.xbox.com/play")
                }
            },
            modifier = Modifier.fillMaxSize()
        )
    }
}
