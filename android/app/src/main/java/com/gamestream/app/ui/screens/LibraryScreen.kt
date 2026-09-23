package com.gamestream.app.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.XboxWebView
import kotlinx.coroutines.delay

@Composable
fun LibraryScreen(session: SessionStore) {
    if (!session.isSignedIn) {
        WelcomeScreen(session)
        return
    }

    if (session.isStreaming) {
        StreamPlayerShell(session)
        return
    }

    GameHub(session = session, modifier = Modifier.fillMaxSize())
}

/** Full-screen stream with chrome that auto-hides (iOS parity). */
@Composable
private fun StreamPlayerShell(session: SessionStore) {
    var chromeVisible by remember { mutableStateOf(false) }

    LaunchedEffect(chromeVisible, session.isStreaming) {
        if (chromeVisible && session.isStreaming) {
            delay(4000)
            chromeVisible = false
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        XboxWebView(session = session, modifier = Modifier.fillMaxSize())

        // Tap empty area to toggle chrome
        Box(
            Modifier
                .fillMaxSize()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) { chromeVisible = !chromeVisible }
        )

        AnimatedVisibility(
            visible = chromeVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .statusBarsPadding()
        ) {
            Surface(
                color = Color(0xCC0A0A12),
                shape = RoundedCornerShape(bottomStart = 16.dp, bottomEnd = 16.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    TextButton(onClick = { session.exitStreamToHub() }) {
                        Icon(Icons.AutoMirrored.Filled.ExitToApp, contentDescription = null, tint = Color.White)
                        Text("  Exit", color = Color.White)
                    }
                    if (session.queuedGames().isNotEmpty()) {
                        TextButton(onClick = { session.playNextFromStream() }) {
                            Text("Play next", color = MaterialTheme.colorScheme.primary)
                        }
                    }
                    TextButton(onClick = { session.returnToHub() }) {
                        Icon(Icons.Default.Home, contentDescription = null, tint = Color.White)
                        Text("  Hub", color = Color.White)
                    }
                }
            }
        }

        // Peek control when chrome is hidden
        AnimatedVisibility(
            visible = !chromeVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(top = 8.dp)
        ) {
            Box(
                Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color(0x66000000))
                    .clickable { chromeVisible = true },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.KeyboardArrowDown,
                    contentDescription = "Show controls",
                    tint = Color.White.copy(alpha = 0.9f)
                )
            }
        }
    }
}
