package com.gamestream.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gamestream.app.AppearancePrefs
import com.gamestream.app.ControllerRumble
import com.gamestream.app.SessionStore
import java.util.Locale

@Composable
fun SettingsScreen(session: SessionStore) {
    val resolutions = listOf("Auto", "720p", "1080p", "1080p HQ")
    val regions = listOf("Auto", "North America", "Europe", "Asia", "Australia")
    val activity = session.activity()
    val top = activity.rankedThisWeek().firstOrNull()
    val last = session.recentGames().firstOrNull()
    val context = LocalContext.current
    val appearance = remember { AppearancePrefs(context) }
    val rumble = remember { ControllerRumble.get(context) }

    var mode by remember { mutableStateOf(appearance.mode) }
    var accent by remember { mutableStateOf(appearance.accent) }
    var background by remember { mutableStateOf(appearance.background) }
    var customBg by remember { mutableStateOf(appearance.customBgColor) }
    var cardStyle by remember { mutableStateOf(appearance.cardStyle) }
    var density by remember { mutableStateOf(appearance.density) }
    var hubLayout by remember { mutableStateOf(appearance.hubLayout) }
    var animation by remember { mutableStateOf(appearance.animation) }
    var effects by remember { mutableStateOf(appearance.effects) }
    var uiSounds by remember { mutableStateOf(appearance.uiSounds) }
    var controllerHaptics by remember { mutableStateOf(appearance.controllerHaptics) }
    var rumbleIntensity by remember { mutableFloatStateOf(appearance.rumbleIntensity) }
    var showActivity by remember { mutableStateOf(appearance.showActivityOnHome) }
    var showGenres by remember { mutableStateOf(appearance.showGenreFilters) }
    var testNote by remember { mutableStateOf("") }

    val intensityLabel = when {
        rumbleIntensity < 0.85f -> "Light"
        rumbleIntensity < 1.35f -> "Normal"
        rumbleIntensity < 2.0f -> "Strong"
        rumbleIntensity < 2.6f -> "Heavy"
        else -> "Max"
    }

    val bgColors = listOf(
        "deepBlack" to Color(0xFF0A0A12),
        "charcoal" to Color(0xFF1E1E24),
        "navy" to Color(0xFF0F1A38),
        "forest" to Color(0xFF0D241A),
        "plum" to Color(0xFF240F2E),
        "wine" to Color(0xFF2E0D1A),
        "slate" to Color(0xFF1A1E29),
        "white" to Color(0xFFF5F5FA)
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold), color = Color.White)

        Category("Account") {
            Text(session.accountLabel ?: "Not signed in", color = Color(0xFFB0B0B8))
        }

        Category("Controller test") {
            ToggleRow("Controller haptics", controllerHaptics) {
                controllerHaptics = it; appearance.controllerHaptics = it
            }
            Spacer(Modifier.height(8.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Rumble intensity", style = MaterialTheme.typography.labelLarge, color = Color(0xFFB0B0B8))
                Spacer(Modifier.weight(1f))
                Text(
                    "$intensityLabel · ${String.format(Locale.US, "%.1f", rumbleIntensity)}×",
                    style = MaterialTheme.typography.labelLarge,
                    color = Color.White
                )
            }
            Slider(
                value = rumbleIntensity,
                onValueChange = {
                    rumbleIntensity = it
                    appearance.rumbleIntensity = it
                },
                valueRange = 0.5f..3f,
                steps = 24,
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "Higher values push motors harder — useful for weak wired controllers.",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF808088)
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = {
                    rumble.playTest()
                    testNote = "Pulse sent — you should feel two bursts (phone and/or pad)."
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Test rumble")
            }
            if (testNote.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                Text(testNote, style = MaterialTheme.typography.bodySmall, color = Color(0xFFB0B0B8))
            }
        }

        Category("Appearance") {
            SettingChips("Theme", listOf("system", "light", "dark"), mode) { mode = it; appearance.mode = it }
            SettingChips("Accent", listOf("violet", "azure", "emerald", "crimson", "gold", "rose", "cyan", "mono"), accent) {
                accent = it; appearance.accent = it
            }
        }

        Category("Background") {
            SettingChips(
                "Style",
                listOf("aurora", "still", "solid", "mesh", "dusk", "midnight", "customColor"),
                background
            ) {
                background = it; appearance.background = it
            }
            if (background == "customColor" || background == "solid") {
                Text("Color", style = MaterialTheme.typography.labelLarge, color = Color(0xFFB0B0B8))
                Spacer(Modifier.height(8.dp))
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    bgColors.forEach { (key, color) ->
                        Box(
                            Modifier
                                .size(36.dp)
                                .clip(CircleShape)
                                .background(color)
                                .then(
                                    if (customBg == key) Modifier.border(2.dp, Color.White, CircleShape)
                                    else Modifier
                                )
                                .clickable {
                                    customBg = key
                                    appearance.customBgColor = key
                                    if (background != "customColor" && background != "solid") {
                                        background = "customColor"
                                        appearance.background = "customColor"
                                    }
                                }
                        )
                    }
                }
            }
            Text(
                "Aurora · Still · Solid · Mesh · Dusk · Midnight, or a custom solid color.",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF808088)
            )
        }

        Category("Library") {
            SettingChips("Home layout", listOf("editorial", "rails", "grid"), hubLayout) {
                hubLayout = it; appearance.hubLayout = it
            }
            SettingChips("Game cards", listOf("poster", "wide", "compact"), cardStyle) {
                cardStyle = it; appearance.cardStyle = it
            }
            SettingChips("Density", listOf("spacious", "comfortable", "compact"), density) {
                density = it; appearance.density = it
            }
            ToggleRow("Activity on home", showActivity) {
                showActivity = it; appearance.showActivityOnHome = it
            }
            ToggleRow("Genre filter row", showGenres) {
                showGenres = it; appearance.showGenreFilters = it
            }
        }

        Category("Motion & effects") {
            SettingChips("Motion", listOf("full", "reduced", "off"), animation) {
                animation = it; appearance.animation = it
            }
            SettingChips("Effects", listOf("quality", "balanced", "performance"), effects) {
                effects = it; appearance.effects = it
            }
        }

        Category("Sound") {
            ToggleRow("UI sounds", uiSounds) {
                uiSounds = it; appearance.uiSounds = it
            }
        }

        Category("Playback") {
            Text(
                last?.title ?: "Play a game and Resume will appear here.",
                color = Color(0xFFB0B0B8),
                maxLines = 1
            )
            Spacer(Modifier.height(8.dp))
            ToggleRow("Resume last game on launch", session.resumeLastOnOpen) {
                session.updateResumeLastOnOpen(it)
            }
            if (last != null) {
                Spacer(Modifier.height(8.dp))
                Button(onClick = { session.resumeLastStream() }, modifier = Modifier.fillMaxWidth()) {
                    Text("Resume ${last.title}", maxLines = 1)
                }
            }
        }

        Category("This week") {
            Text(
                "${activity.format(activity.weekTotal())} streamed on this device",
                color = Color(0xFFB0B0B8)
            )
            if (top != null) {
                Text("Most played: ${top.title}", style = MaterialTheme.typography.bodySmall, color = Color(0xFF808088))
            }
        }

        Category("Stream") {
            Text("Applied to Better xCloud and reloads the page.", style = MaterialTheme.typography.bodySmall, color = Color(0xFF808088))
            Spacer(Modifier.height(8.dp))
            Text("Resolution", style = MaterialTheme.typography.labelLarge, color = Color(0xFFB0B0B8))
            SettingChipsRow(resolutions, session.streamResolution) { session.applyResolution(it) }
            Spacer(Modifier.height(8.dp))
            Text("Region", style = MaterialTheme.typography.labelLarge, color = Color(0xFFB0B0B8))
            SettingChipsRow(regions, session.serverRegion) { session.applyRegion(it) }
        }

        Category("Actions") {
            Button(onClick = { session.openHome() }, modifier = Modifier.fillMaxWidth()) { Text("Open Library") }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { session.clearCache(context) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Clear cache")
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(onClick = { session.refreshBetterXCloud() }, modifier = Modifier.fillMaxWidth()) {
                Text("Refresh Better xCloud script")
            }
            if (session.isSignedIn) {
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = { session.signOut() }, modifier = Modifier.fillMaxWidth()) {
                    Text("Sign Out")
                }
            }
        }

        Category("About") {
            Text(
                "GameStream Android — library layouts, backgrounds, and controller rumble parity with iOS.",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF808088)
            )
            Spacer(Modifier.height(8.dp))
            Text("Made with 🤍 by Bestin", fontWeight = FontWeight.SemiBold, color = Color.White)
        }

        Spacer(Modifier.height(40.dp))
    }
}

@Composable
private fun Category(title: String, content: @Composable () -> Unit) {
    Spacer(Modifier.height(20.dp))
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF16161E))
            .padding(16.dp)
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold), color = Color.White)
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Color.White, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun SettingChips(label: String, options: List<String>, selected: String, onSelect: (String) -> Unit) {
    Text(label, style = MaterialTheme.typography.labelLarge, color = Color(0xFFB0B0B8))
    Spacer(Modifier.height(6.dp))
    SettingChipsRow(options, selected, onSelect)
    Spacer(Modifier.height(10.dp))
}

@Composable
private fun SettingChipsRow(options: List<String>, selected: String, onSelect: (String) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
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
