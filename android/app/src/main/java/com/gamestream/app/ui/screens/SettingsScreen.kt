package com.gamestream.app.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gamestream.app.AppearancePrefs
import com.gamestream.app.SessionStore

@Composable
fun SettingsScreen(session: SessionStore) {
    val resolutions = listOf("Auto", "720p", "1080p", "1080p HQ")
    val regions = listOf("Auto", "North America", "Europe", "Asia", "Australia")
    val activity = session.activity()
    val top = activity.rankedThisWeek().firstOrNull()
    val last = session.recentGames().firstOrNull()
    val context = LocalContext.current
    val appearance = remember { AppearancePrefs(context) }
    var mode by remember { mutableStateOf(appearance.mode) }
    var accent by remember { mutableStateOf(appearance.accent) }
    var background by remember { mutableStateOf(appearance.background) }
    var cardStyle by remember { mutableStateOf(appearance.cardStyle) }
    var density by remember { mutableStateOf(appearance.density) }
    var animation by remember { mutableStateOf(appearance.animation) }
    var effects by remember { mutableStateOf(appearance.effects) }
    var uiSounds by remember { mutableStateOf(appearance.uiSounds) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Text(
            "Settings",
            style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold),
            color = Color.White
        )

        Spacer(modifier = Modifier.height(20.dp))
        Text("Account", style = MaterialTheme.typography.titleMedium, color = Color.White)
        Text(
            session.accountLabel ?: "Not signed in",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFFB0B0B8)
        )

        Spacer(modifier = Modifier.height(20.dp))
        Text("Jump back in", style = MaterialTheme.typography.titleMedium, color = Color.White)
        Text(
            last?.title ?: "Play a game and Resume will appear here.",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFFB0B0B8),
            maxLines = 1
        )
        Spacer(modifier = Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Resume last game on launch", color = Color.White, modifier = Modifier.weight(1f), maxLines = 2)
            Switch(checked = session.resumeLastOnOpen, onCheckedChange = { session.updateResumeLastOnOpen(it) })
        }
        if (last != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Button(onClick = { session.resumeLastStream() }, modifier = Modifier.fillMaxWidth()) {
                Text("Resume ${last.title}", maxLines = 1)
            }
        }

        Spacer(modifier = Modifier.height(20.dp))
        Text("This week", style = MaterialTheme.typography.titleMedium, color = Color.White)
        Text(
            "${activity.format(activity.weekTotal())} streamed on this device",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFFB0B0B8)
        )
        if (top != null) {
            Text(
                "Most played: ${top.title}",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF808088)
            )
        }

        Spacer(modifier = Modifier.height(20.dp))
        Text("Stream", style = MaterialTheme.typography.titleMedium, color = Color.White)
        Text(
            "Applied to Better xCloud and reloads the page.",
            style = MaterialTheme.typography.bodySmall,
            color = Color(0xFF808088)
        )

        Spacer(modifier = Modifier.height(8.dp))
        Text("Target resolution", style = MaterialTheme.typography.labelLarge, color = Color(0xFFB0B0B8))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            resolutions.forEach { opt ->
                FilterChip(
                    selected = session.streamResolution == opt,
                    onClick = { session.applyResolution(opt) },
                    label = { Text(opt) }
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))
        Text("Server region", style = MaterialTheme.typography.labelLarge, color = Color(0xFFB0B0B8))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            regions.forEach { opt ->
                FilterChip(
                    selected = session.serverRegion == opt,
                    onClick = { session.applyRegion(opt) },
                    label = { Text(opt) }
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))
        Text("Look", style = MaterialTheme.typography.titleMedium, color = Color.White)
        SettingChips("Appearance", listOf("system", "light", "dark"), mode) {
            mode = it
            appearance.mode = it
        }
        SettingChips("Accent", listOf("violet", "green", "blue", "orange"), accent) {
            accent = it
            appearance.accent = it
        }
        SettingChips("Background", listOf("aurora", "solid", "dim"), background) {
            background = it
            appearance.background = it
        }
        SettingChips("Game cards", listOf("poster", "wide", "compact"), cardStyle) {
            cardStyle = it
            appearance.cardStyle = it
        }
        SettingChips("Library density", listOf("comfortable", "compact"), density) {
            density = it
            appearance.density = it
        }
        SettingChips("Motion", listOf("full", "reduced", "off"), animation) {
            animation = it
            appearance.animation = it
        }
        SettingChips("Effects", listOf("quality", "balanced", "performance"), effects) {
            effects = it
            appearance.effects = it
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("UI sounds", color = Color.White, modifier = Modifier.weight(1f), maxLines = 1)
            Switch(checked = uiSounds, onCheckedChange = {
                uiSounds = it
                appearance.uiSounds = it
            })
        }

        Spacer(modifier = Modifier.height(24.dp))
        Text("Actions", style = MaterialTheme.typography.titleMedium, color = Color.White)
        Spacer(modifier = Modifier.height(8.dp))
        Button(
            onClick = { session.openHome() },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Open Library") }
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedButton(
            onClick = { session.refreshBetterXCloud() },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Refresh Better xCloud script") }
        if (session.isSignedIn) {
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(
                onClick = { session.signOut() },
                modifier = Modifier.fillMaxWidth()
            ) { Text("Sign Out") }
        }

        Spacer(modifier = Modifier.height(24.dp))
        Text("About", style = MaterialTheme.typography.titleMedium, color = Color.White)
        Text(
            "GameStream Android 1.3.3 — native WebView client for Xbox Cloud Gaming with Better xCloud.",
            style = MaterialTheme.typography.bodySmall,
            color = Color(0xFF808088)
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Made with ❤️ by Bestin",
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = Color.White
        )
        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
private fun SettingChips(label: String, options: List<String>, selected: String, onSelect: (String) -> Unit) {
    Spacer(modifier = Modifier.height(8.dp))
    Text(label, style = MaterialTheme.typography.labelLarge, color = Color(0xFFB0B0B8))
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        options.forEach { opt ->
            FilterChip(
                selected = selected == opt,
                onClick = { onSelect(opt) },
                label = { Text(opt.replaceFirstChar { it.uppercase() }) }
            )
        }
    }
}
