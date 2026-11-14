package com.gamestream.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.gamestream.app.ArtworkStore
import com.gamestream.app.CatalogGame
import com.gamestream.app.CollectionStore
import com.gamestream.app.GameCatalog
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.XboxWebView
import com.gamestream.app.ui.theme.Radius

/**
 * Library: everything the player has, the way the iOS app lays it out.
 *
 * The Android app opened this tab on a copy of the old hub — one long
 * list of every game in the catalogue with filters across the top. The
 * iOS app opens on the player's own shelves instead: what they saved,
 * what they were playing, what is queued, and the catalogue last. The
 * full catalogue is still one tap away on the Browse row.
 */
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

    val context = LocalContext.current
    val collectionStore = remember(context) { CollectionStore(context) }
    val collections = collectionStore.collections()

    val favorites = session.favoriteGames().take(12)
    val recents = session.recentGames().take(12)
    val queued = session.queuedGames()
    val cloud = GameCatalog.games.take(24)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 28.dp)
    ) {
        Column(Modifier.padding(horizontal = 20.dp, vertical = 10.dp)) {
            Text(
                text = "Library",
                color = Color.White,
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "${favorites.size} saved · ${queued.size} queued",
                color = Color.White.copy(alpha = 0.6f),
                style = MaterialTheme.typography.labelSmall
            )
        }

        if (favorites.isNotEmpty()) {
            Shelf("Favorites", "${favorites.size} saved", favorites, session)
        }
        if (recents.isNotEmpty()) {
            Shelf("Jump back in", "Where you left off", recents, session)
        }
        if (queued.isNotEmpty()) {
            Shelf(
                "Up next",
                queueDetail(session.activity(), queued),
                queued,
                session
            )
        }
        collections.forEach { collection ->
            val games = collectionStore.games(collection)
            if (games.isNotEmpty()) {
                Shelf(collection.name, "${games.size} games", games, session)
            }
        }
        Shelf("In the cloud", "${cloud.size} games ready to stream", cloud, session)
    }
}

/** How long the queue is likely to take, from how long this player plays. */
private fun queueDetail(
    activity: com.gamestream.app.PlayActivity,
    queue: List<CatalogGame>
): String {
    if (queue.isEmpty()) return ""
    val seconds = queue.sumOf { activity.estimatedSeconds(it.id) }
    val noun = if (queue.size == 1) "game" else "games"
    if (seconds <= 0L) return "${queue.size} $noun"
    return "${queue.size} $noun · about ${activity.format(seconds)} left"
}

@Composable
private fun Shelf(
    title: String,
    subtitle: String,
    games: List<CatalogGame>,
    session: SessionStore
) {
    Column(Modifier.padding(bottom = 22.dp)) {
        Column(Modifier.padding(horizontal = 20.dp, vertical = 6.dp)) {
            Text(
                text = title,
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            if (subtitle.isNotBlank()) {
                Text(
                    text = subtitle,
                    color = Color.White.copy(alpha = 0.6f),
                    style = MaterialTheme.typography.labelSmall
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        LazyRow(
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            items(games, key = { it.id }) { game ->
                ShelfCard(game = game, onPlay = { session.playGame(game) })
            }
        }
    }
}

@Composable
private fun ShelfCard(game: CatalogGame, onPlay: () -> Unit) {
    Column(Modifier.width(124.dp)) {
        Box(
            Modifier
                .size(width = 124.dp, height = 165.dp)
                .clip(RoundedCornerShape(Radius.tile))
                .background(Color(0xFF1A1A24))
                .clickable { onPlay() }
        ) {
            val url = ArtworkStore.urlFor(game)
            if (url != null) {
                AsyncImage(
                    model = url,
                    contentDescription = game.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        game.title.take(1),
                        color = Color.White,
                        style = MaterialTheme.typography.headlineMedium
                    )
                }
            }
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .padding(8.dp)
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f))
                    .clickable { onPlay() },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Filled.PlayArrow,
                    contentDescription = "Play ${game.title}",
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
        Spacer(Modifier.height(7.dp))
        Text(
            text = game.title,
            color = Color.White,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = game.genre,
            color = Color.White.copy(alpha = 0.55f),
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
