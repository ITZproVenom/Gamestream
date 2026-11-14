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
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.gamestream.app.ArtworkStore
import com.gamestream.app.CatalogGame
import com.gamestream.app.GameCatalog
import com.gamestream.app.PlayActivity
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.theme.GlassCard
import com.gamestream.app.ui.theme.LocalAccent
import com.gamestream.app.ui.theme.Radius

/**
 * Home: the iOS app's first screen, on Android.
 *
 * The Android app opened on a list of games with no home at all. This is
 * the same arrangement as the iOS one: a hero, what you played, the queue
 * and its time, your favourites, and the catalogue.
 */
@Composable
fun HomeScreen(session: SessionStore) {
    val context = LocalContext.current
    val activity = PlayActivity.get(context)
    val featured = GameCatalog.games.firstOrNull { it.featured }
        ?: GameCatalog.games.firstOrNull()
    val recents = session.recentIds.mapNotNull { GameCatalog.find(it) }.take(12)
    val queue = session.queueIds.mapNotNull { GameCatalog.find(it) }
    val favorites = session.favoriteIds.mapNotNull { GameCatalog.find(it) }.take(12)
    val cloud = GameCatalog.games.take(24)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 28.dp)
    ) {
        if (featured != null) {
            HeroCard(
                game = featured,
                onPlay = { session.playGame(featured) }
            )
            Spacer(Modifier.height(18.dp))
        }

        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            StatCard(
                value = activity.format(activity.weekTotal()),
                caption = "Played this week",
                modifier = Modifier.weight(1f)
            )
            StatCard(
                value = "${activity.totalSessionCount()}",
                caption = "Sessions",
                modifier = Modifier.weight(1f)
            )
            StatCard(
                value = "${session.queueIds.size}",
                caption = "Up next",
                modifier = Modifier.weight(1f)
            )
        }

        Spacer(Modifier.height(24.dp))

        if (recents.isNotEmpty()) {
            Shelf("Jump back in", "Where you left off", recents, session)
        }
        if (queue.isNotEmpty()) {
            Shelf("Up next", queueDetail(activity, queue), queue, session)
        }
        if (favorites.isNotEmpty()) {
            Shelf("Favorites", "${favorites.size} saved", favorites, session)
        }
        Shelf("In the cloud", "${cloud.size} games ready to stream", cloud, session)
    }
}

/** How long the queue is likely to take, from how long this player plays. */
private fun queueDetail(activity: PlayActivity, queue: List<CatalogGame>): String {
    if (queue.isEmpty()) return ""
    val seconds = queue.sumOf { activity.estimatedSeconds(it.id) }
    val noun = if (queue.size == 1) "game" else "games"
    if (seconds <= 0L) return "${queue.size} $noun"
    return "${queue.size} $noun · about ${activity.format(seconds)} left"
}

@Composable
private fun HeroCard(game: CatalogGame, onPlay: () -> Unit) {
    val accent = LocalAccent.current
    Box(
        Modifier
            .fillMaxWidth()
            .height(280.dp)
            .clip(RoundedCornerShape(Radius.hero))
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
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color(0xFF1A1A24)),
                contentAlignment = Alignment.Center
            ) {
                Text(game.title.take(1), color = Color.White, style = MaterialTheme.typography.displayLarge)
            }
        }
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0f to Color.Transparent,
                        0.45f to Color.Black.copy(alpha = 0.55f),
                        1f to Color.Black.copy(alpha = 0.88f)
                    )
                )
        )
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .padding(20.dp)
        ) {
            Text(
                text = game.genre.uppercase(),
                color = Color.White.copy(alpha = 0.75f),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = game.title,
                color = Color.White,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = onPlay,
                colors = ButtonDefaults.buttonColors(containerColor = accent.color),
                shape = RoundedCornerShape(999.dp)
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Play")
            }
        }
    }
}

@Composable
private fun StatCard(value: String, caption: String, modifier: Modifier = Modifier) {
    GlassCard(modifier = modifier, contentPadding = PaddingValues(14.dp)) {
        Text(
            text = value,
            color = Color.White,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = caption,
            color = Color.White.copy(alpha = 0.62f),
            style = MaterialTheme.typography.labelSmall,
            maxLines = 2
        )
    }
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
                    Text(game.title.take(1), color = Color.White, style = MaterialTheme.typography.headlineMedium)
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
