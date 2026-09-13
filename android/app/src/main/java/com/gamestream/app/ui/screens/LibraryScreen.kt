package com.gamestream.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.XboxWebView

@Composable
fun LibraryScreen(session: SessionStore) {
    if (!session.isSignedIn) {
        WelcomeScreen(session)
        return
    }

    Box(Modifier.fillMaxSize()) {
        XboxWebView(session = session, modifier = Modifier.fillMaxSize())

        if (session.showNativeHub && !session.isStreaming) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Start
                ) {
                    GameHubListsButton(session)
                }
                GameHub(session = session, modifier = Modifier.fillMaxSize())
            }
        } else if (!session.isStreaming) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp)
                    .align(Alignment.TopCenter),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = { session.returnToHub() },
                    modifier = Modifier.clip(RoundedCornerShape(12.dp)).background(Color(0xCC1C1C24))
                ) {
                    Icon(Icons.Default.Home, contentDescription = "Hub", tint = Color.White)
                }
                IconButton(
                    onClick = { session.reloadCurrent() },
                    modifier = Modifier.clip(RoundedCornerShape(12.dp)).background(Color(0xCC1C1C24))
                ) {
                    Icon(Icons.Default.Refresh, contentDescription = "Reload", tint = Color.White)
                }
            }
        }
    }
}
