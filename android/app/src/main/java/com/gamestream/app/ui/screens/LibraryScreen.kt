package com.gamestream.app.ui.screens

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.XboxWebView

@Composable
fun LibraryScreen(session: SessionStore) {
    if (!session.isSignedIn) {
        SignInPrompt(onSignIn = { session.markSignedIn() })
        return
    }

    Box(Modifier.fillMaxSize()) {
        XboxWebView(session = session, modifier = Modifier.fillMaxSize())

        if (!session.isStreaming) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dpSafe())
                    .align(Alignment.TopCenter),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = { session.openHome() },
                    modifier = Modifier
                        .clip(RoundedCornerShape(12))
                        .background(Color(0xCC1C1C24))
                ) {
                    Icon(Icons.Default.Home, contentDescription = "Home", tint = Color.White)
                }
                IconButton(
                    onClick = { session.reloadCurrent() },
                    modifier = Modifier
                        .clip(RoundedCornerShape(12))
                        .background(Color(0xCC1C1C24))
                ) {
                    Icon(Icons.Default.Refresh, contentDescription = "Reload", tint = Color.White)
                }
            }
        }
    }
}

@Composable
private fun SignInPrompt(onSignIn: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(28.dpSafe()),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.SportsEsports,
            contentDescription = null,
            tint = Color(0xFF8B7CFF),
            modifier = Modifier.height(56.dpSafe())
        )
        Spacer(Modifier.height(16.dpSafe()))
        Text(
            "Your Library",
            style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
            color = Color.White
        )
        Spacer(Modifier.height(8.dpSafe()))
        Text(
            "Sign in with your Xbox account to load games from Xbox Cloud Gaming.",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFFB0B0B8),
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(24.dpSafe()))
        Button(onClick = onSignIn) {
            Text("Continue to Xbox Cloud")
        }
        Spacer(Modifier.height(8.dpSafe()))
        Text(
            "You'll sign in inside the web session. Cookies stay on this device.",
            style = MaterialTheme.typography.labelSmall,
            color = Color(0xFF808088),
            textAlign = TextAlign.Center
        )
    }
}

/** Avoid needing foundation.dp import everywhere in tiny helpers */
@Composable
private fun Int.dpSafe() = androidx.compose.ui.unit.Dp(this.toFloat())
