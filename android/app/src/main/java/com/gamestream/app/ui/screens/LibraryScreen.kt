package com.gamestream.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.XboxWebView

@Composable
fun LibraryScreen(session: SessionStore) {
    if (!session.isSignedIn) {
        WelcomeScreen(session)
        return
    }

    if (session.isStreaming) {
        Box(Modifier.fillMaxSize()) {
            XboxWebView(session = session, modifier = Modifier.fillMaxSize())
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp)
                    .align(Alignment.TopStart),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedButton(onClick = { session.exitStreamToHub() }) {
                    Text("Exit", maxLines = 1)
                }
                if (session.queuedGames().isNotEmpty()) {
                    Button(onClick = { session.playNextFromStream() }) {
                        Text("Play next", maxLines = 1)
                    }
                }
                OutlinedButton(onClick = { session.returnToHub() }) {
                    Text("Hub", maxLines = 1)
                }
            }
        }
        return
    }

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
}
