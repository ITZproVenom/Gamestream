package com.gamestream.app.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.gamestream.app.ArtworkStore
import com.gamestream.app.CatalogGame
import com.gamestream.app.GameCatalog
import com.gamestream.app.SessionStore

@Composable
fun GameHub(session: SessionStore, modifier: Modifier = Modifier) {
    var query by remember { mutableStateOf("") }
    var detail by remember { mutableStateOf<CatalogGame?>(null) }
    val filtering = query.isNotBlank()
    val matches = remember(query) { GameCatalog.matches(query) }
    val shelves = remember(session.favoriteIds, session.recentIds, session.queueIds) {
        buildList {
            val queued = session.queuedGames()
            if (queued.isNotEmpty()) add("Up Next" to queued)
            val recents = session.recentGames()
            if (recents.isNotEmpty()) add("Continue playing" to recents)
            val favs = session.favoriteGames()
            if (favs.isNotEmpty()) add("Favorites" to favs)
            add("Popular on Cloud" to GameCatalog.games.take(8))
            GameCatalog.games.groupBy { it.genre }.forEach { (genre, items) ->
                if (items.size >= 2) add(genre to items)
            }
        }
    }

    Column(
        modifier
            .fillMaxSize()
            .background(Color(0xFF0A0A12))
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Text("GameStream", style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold), color = Color.White)
        Text("Xbox Cloud Gaming", style = MaterialTheme.typography.bodyMedium, color = Color(0xFFB0B0B8))
        Spacer(Modifier.height(14.dp))
        OutlinedTextField(value = query, onValueChange = { query = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text("Search games") }, singleLine = true)
        if (filtering) {
            Spacer(Modifier.height(12.dp))
            Text(
                if (matches.isEmpty()) "No catalog matches" else "Matching games",
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                color = Color.White
            )
            Spacer(Modifier.height(8.dp))
            if (matches.isEmpty()) {
                Text("No local catalog titles match this search.", color = Color(0xFFB0B0B8))
            } else {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    matches.forEach { game ->
                        PosterCard(game, session.isFavorite(game.id), onOpen = { detail = game }, onPlay = { session.playGame(game) }, onFav = { session.toggleFavorite(game) })
                    }
                }
            }
            TextButton(onClick = { session.openSearch(query) }) {
                Text("Search Xbox Cloud for \"${query.trim()}\"")
            }
        } else {
            if (session.queuedGames().isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Button(onClick = { session.playNextQueued() }, modifier = Modifier.fillMaxWidth()) {
                    Text("Play next in queue")
                }
            }
            Spacer(Modifier.height(16.dp))
            Text("Featured", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
            Spacer(Modifier.height(8.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                GameCatalog.featured.forEach { game ->
                    FeaturedCard(game, session.isFavorite(game.id), onPlay = { session.playGame(game) }, onFav = { session.toggleFavorite(game) }, onOpen = { detail = game })
                }
            }
            shelves.forEach { (title, games) ->
                Spacer(Modifier.height(18.dp))
                Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
                Spacer(Modifier.height(8.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    games.forEach { game ->
                        PosterCard(game, session.isFavorite(game.id), onOpen = { detail = game }, onPlay = { session.playGame(game) }, onFav = { session.toggleFavorite(game) })
                    }
                }
            }
            Spacer(Modifier.height(20.dp))
            Button(onClick = { session.openXboxCloud() }, modifier = Modifier.fillMaxWidth()) {
                Text("Full Xbox Cloud library")
            }
        }
        Spacer(Modifier.height(80.dp))
    }

    detail?.let { game ->
        AlertDialog(
            onDismissRequest = { detail = null },
            title = { Text(game.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
            text = {
                Column {
                    Text(game.tagline)
                    Spacer(Modifier.height(8.dp))
                    Text("${game.genre} · ${game.provider}", color = Color(0xFF808088))
                }
            },
            confirmButton = {
                Button(onClick = { session.playGame(game); detail = null }) { Text("Play now") }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = { session.toggleFavorite(game) }) {
                        Text(if (session.isFavorite(game.id)) "Unfavorite" else "Favorite")
                    }
                    TextButton(onClick = { session.toggleQueue(game) }) {
                        Text(if (session.isQueued(game.id)) "Queued" else "Up Next")
                    }
                    OutlinedButton(onClick = { session.openGame(game); detail = null }) { Text("Open") }
                }
            }
        )
    }
}

@Composable
private fun FeaturedCard(game: CatalogGame, favorite: Boolean, onPlay: () -> Unit, onFav: () -> Unit, onOpen: () -> Unit) {
    Box(Modifier.width(280.dp).height(168.dp).clip(RoundedCornerShape(20.dp)).background(Color(game.accent)).clickable(onClick = onOpen)) {
        Artwork(game, Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f)))))
        Column(Modifier.align(Alignment.BottomStart).padding(14.dp)) {
            Text(game.provider, color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.labelSmall, maxLines = 1)
            Text(game.title, color = Color.White, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(game.tagline, color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = onPlay) { Text("Play") }
                IconButton(onClick = onFav) {
                    Icon(if (favorite) Icons.Filled.Star else Icons.Outlined.StarBorder, contentDescription = "Favorite", tint = Color.White)
                }
            }
        }
    }
}

@Composable
private fun PosterCard(game: CatalogGame, favorite: Boolean, onOpen: () -> Unit, onPlay: () -> Unit, onFav: () -> Unit) {
    Column(Modifier.width(120.dp)) {
        Box(Modifier.size(120.dp, 156.dp).clip(RoundedCornerShape(14.dp)).background(Color(game.accent)).clickable(onClick = onOpen)) {
            Artwork(game, Modifier.fillMaxSize())
            IconButton(onClick = onFav, modifier = Modifier.align(Alignment.TopEnd).background(Color.Black.copy(alpha = 0.35f), CircleShape)) {
                Icon(if (favorite) Icons.Filled.Star else Icons.Outlined.StarBorder, contentDescription = "Favorite", tint = Color.White)
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(game.title, color = Color.White, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(game.provider, color = Color(0xFF808088), style = MaterialTheme.typography.labelSmall, maxLines = 1)
        TextButton(onClick = onPlay) { Text("Play") }
    }
}

@Composable
private fun Artwork(game: CatalogGame, modifier: Modifier = Modifier) {
    val url = ArtworkStore.urlFor(game)
    if (url != null) {
        AsyncImage(
            model = url,
            contentDescription = game.title,
            modifier = modifier,
            contentScale = ContentScale.Crop
        )
    } else {
        Box(modifier.background(Color(game.accent)), contentAlignment = Alignment.Center) {
            Text(game.title.take(1), color = Color.White, style = MaterialTheme.typography.headlineLarge)
        }
    }
}
