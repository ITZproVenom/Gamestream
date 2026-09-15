package com.gamestream.app.ui.screens

import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.gamestream.app.GameCatalog
import com.gamestream.app.SearchPrefs
import com.gamestream.app.SessionStore

@Composable
fun SearchScreen(session: SessionStore) {
    val context = LocalContext.current
    val prefs = remember(context) { SearchPrefs(context) }
    var query by remember { mutableStateOf("") }
    var recent by remember { mutableStateOf(prefs.recent()) }
    var pinned by remember { mutableStateOf(prefs.pinned()) }
    val catalogHits = remember(query) { GameCatalog.matches(query).take(8) }
    val popular = remember {
        listOf("Fortnite", "Minecraft", "Call of Duty", "Forza Horizon", "Roblox", "Sea of Thieves")
    }
    val queryPinned = remember(query, pinned) { prefs.isPinned(query) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Text("Search", style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold), color = Color.White)
        Text("Find your next game", style = MaterialTheme.typography.bodyMedium, color = Color(0xFFB0B0B8))
        Spacer(Modifier.height(20.dp))
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Search games") },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = {
                val q = query.trim()
                if (q.isNotEmpty()) {
                    recent = prefs.remember(q)
                    session.openSearch(q)
                }
            })
        )
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Button(
                onClick = {
                    val q = query.trim()
                    if (q.isNotEmpty()) {
                        recent = prefs.remember(q)
                        session.openSearch(q)
                    }
                },
                enabled = query.isNotBlank(),
                modifier = Modifier.weight(1f)
            ) {
                Text("Search Xbox Cloud Gaming", maxLines = 1)
            }
            if (query.isNotBlank()) {
                FilledTonalButton(onClick = { pinned = prefs.togglePin(query) }) {
                    Text(if (queryPinned) "Unpin" else "Pin", maxLines = 1)
                }
            }
        }
        if (pinned.isNotEmpty() && query.isBlank()) {
            Spacer(Modifier.height(20.dp))
            Text("Pinned searches", style = MaterialTheme.typography.titleMedium, color = Color.White)
            pinned.forEach { item ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable {
                        query = item
                        prefs.remember(item)
                        session.openSearch(item)
                    }.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(item, color = Color.White, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    TextButton(onClick = { pinned = prefs.togglePin(item); recent = prefs.recent() }) { Text("Unpin") }
                }
            }
        }
        if (query.isBlank()) {
            session.recentGames().firstOrNull()?.let { last ->
                Spacer(Modifier.height(20.dp))
                Text("Jump back in", style = MaterialTheme.typography.titleMedium, color = Color.White)
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(last.title, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("Resume on Xbox Cloud", color = Color(0xFFB0B0B8), style = MaterialTheme.typography.bodySmall, maxLines = 1)
                    }
                    Button(onClick = { session.resumeLastStream() }) { Text("Resume", maxLines = 1) }
                }
            }
            Spacer(Modifier.height(16.dp))
            Text("Browse genres", style = MaterialTheme.typography.titleMedium, color = Color.White)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GameCatalog.genreNames.forEach { name ->
                    AssistChip(onClick = { query = name }, label = { Text(name, maxLines = 1) })
                }
            }
            Spacer(Modifier.height(16.dp))
            Text("Popular on Cloud", style = MaterialTheme.typography.titleMedium, color = Color.White)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                popular.forEach { title ->
                    AssistChip(onClick = { query = title; prefs.remember(title); session.openSearch(title) }, label = { Text(title, maxLines = 1) })
                }
            }
            if (recent.isNotEmpty()) {
                Spacer(Modifier.height(16.dp))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Recent searches", style = MaterialTheme.typography.titleMedium, color = Color.White, modifier = Modifier.weight(1f))
                    TextButton(onClick = { prefs.clearRecent(); recent = emptyList() }) { Text("Clear") }
                }
                recent.forEach { item ->
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable {
                            query = item
                            prefs.remember(item)
                            session.openSearch(item)
                        }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(item, color = Color.White, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        IconButton(onClick = { pinned = prefs.togglePin(item) }) {
                            Icon(Icons.Default.Star, contentDescription = "Pin search")
                        }
                    }
                }
            }
        } else {
            Spacer(Modifier.height(16.dp))
            Text("In GameHub", style = MaterialTheme.typography.titleMedium, color = Color.White)
            if (catalogHits.isEmpty()) {
                Text("No titles in the local catalog match this search.", color = Color(0xFF808088), style = MaterialTheme.typography.bodySmall)
            } else {
                catalogHits.forEach { game ->
                    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(game.title, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                            Text(game.genre, color = Color(0xFFB0B0B8), style = MaterialTheme.typography.bodySmall, maxLines = 1)
                        }
                        IconButton(onClick = { session.toggleFavorite(game) }) {
                            Icon(Icons.Default.Star, contentDescription = "Favorite", tint = if (session.favoriteIds.contains(game.id)) Color(0xFFFFC107) else Color.White)
                        }
                        IconButton(onClick = { session.playGame(game) }) {
                            Icon(Icons.Default.PlayArrow, contentDescription = "Play ${game.title}")
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(80.dp))
    }
}
