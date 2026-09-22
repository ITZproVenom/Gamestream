package com.gamestream.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.gamestream.app.AppearancePrefs
import com.gamestream.app.ArtworkStore
import com.gamestream.app.CatalogGame
import com.gamestream.app.DiscoveryMode
import com.gamestream.app.ForYouCatalog
import com.gamestream.app.GameCatalog
import com.gamestream.app.GameDiscovery
import com.gamestream.app.SessionStore

private fun accentColor(accent: Long): Color = Color(accent.toInt())

@Composable
fun GameHub(session: SessionStore, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val appearance = remember { AppearancePrefs(context) }
    @Suppress("UNUSED_VARIABLE")
    val rev = appearance.revision

    var query by remember { mutableStateOf("") }
    var detail by remember { mutableStateOf<CatalogGame?>(null) }
    var filter by remember { mutableStateOf("Home") }
    val filtering = query.isNotBlank()
    val matches = remember(query) { GameCatalog.matches(query) }
    val recents = session.recentGames()
    val favs = session.favoriteGames()
    val forYou = remember(session.favoriteIds, session.recentIds) { ForYouCatalog.forYou(favs, recents) }
    val because = remember(session.recentIds) { ForYouCatalog.becauseYouPlayed(recents) }

    val primaryChips = listOf("Home", "Library", "Browse", "For You", "Favorites", "Recents")
    val genreChips = if (appearance.showGenreFilters) {
        DiscoveryMode.entries.map { it.title } + ForYouCatalog.genreNames
    } else {
        emptyList()
    }

    val filteredGames = when (filter) {
        "For You" -> forYou
        "Favorites" -> favs
        "Recents" -> recents
        "Library" -> (favs + recents).distinctBy { it.id }
        "Browse", "Home" -> GameCatalog.games
        else -> GameDiscovery.fromTitle(filter)?.let { GameDiscovery.games(it) }
            ?: GameCatalog.games.filter { it.genre == filter }
    }

    val shelves = remember(session.favoriteIds, session.recentIds, session.queueIds) {
        buildList {
            val queued = session.queuedGames()
            if (queued.isNotEmpty()) add("Up Next" to queued)
            if (recents.isNotEmpty()) add("Continue playing" to recents)
            if (favs.isNotEmpty()) add("Favorites" to favs)
            if (forYou.isNotEmpty()) add("For You" to forYou)
            because.forEach { add(it) }
            add("Popular on Cloud" to GameCatalog.games.take(8))
            addAll(GameDiscovery.shelves())
        }
    }

    val sectionGap = appearance.sectionSpacingDp().dp
    val posterFrac = appearance.posterWidthFraction()
    val bg = Color(appearance.backgroundColorArgb())

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .clipToBounds()
            .background(bg)
    ) {
        val constraintsMaxWidth = maxWidth
        val featuredWidth = (constraintsMaxWidth * 0.88f).coerceIn(260.dp, 340.dp)
        val posterWidth = (constraintsMaxWidth * posterFrac).coerceIn(100.dp, 150.dp)
        val heroHeight = when (appearance.density) {
            "compact" -> 180.dp
            "spacious" -> 240.dp
            else -> 210.dp
        }

        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 14.dp)
        ) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "GameStream",
                        style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
                        color = Color.White,
                        maxLines = 1
                    )
                    Text("Xbox Cloud Gaming", style = MaterialTheme.typography.bodySmall, color = Color(0xFFB0B0B8))
                }
                OutlinedButton(onClick = { session.openXboxCloud() }) {
                    Text("Cloud", maxLines = 1)
                }
            }

            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Search games") },
                singleLine = true
            )

            if (filtering) {
                Spacer(Modifier.height(sectionGap))
                Text(
                    if (matches.isEmpty()) "No matches" else "Results",
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                    color = Color.White
                )
                Spacer(Modifier.height(10.dp))
                if (matches.isEmpty()) {
                    Text("No local catalog titles match this search.", color = Color(0xFFB0B0B8))
                } else {
                    PosterRow(matches, session, posterWidth) { detail = it }
                }
                TextButton(onClick = { session.openSearch(query) }) {
                    Text("Search Xbox Cloud for \"${query.trim()}\"")
                }
            } else {
                Spacer(Modifier.height(14.dp))
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    primaryChips.forEach { chip ->
                        FilterChip(
                            selected = filter == chip,
                            onClick = { filter = chip },
                            label = { Text(chip) }
                        )
                    }
                }
                if (genreChips.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Row(
                        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        genreChips.forEach { chip ->
                            FilterChip(
                                selected = filter == chip,
                                onClick = { filter = chip },
                                label = { Text(chip, maxLines = 1) }
                            )
                        }
                    }
                }

                when (filter) {
                    "Home" -> {
                        Spacer(Modifier.height(sectionGap))
                        when (appearance.hubLayout) {
                            "editorial" -> {
                                GameCatalog.featured.firstOrNull()?.let { hero ->
                                    FeaturedCard(
                                        game = hero,
                                        favorite = session.isFavorite(hero.id),
                                        onPlay = { session.playGame(hero) },
                                        onFav = { session.toggleFavorite(hero) },
                                        onOpen = { detail = hero },
                                        width = (constraintsMaxWidth - 36.dp).coerceAtLeast(200.dp),
                                        height = heroHeight
                                    )
                                }
                                Spacer(Modifier.height(sectionGap))
                                ContinueCard(recents.firstOrNull(), session) { detail = it }
                                if (appearance.showActivityOnHome) {
                                    Spacer(Modifier.height(sectionGap))
                                    ActivityStrip(session)
                                }
                                shelves.forEach { (title, games) ->
                                    Spacer(Modifier.height(sectionGap))
                                    Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 1)
                                    Spacer(Modifier.height(10.dp))
                                    PosterRow(games, session, posterWidth) { detail = it }
                                }
                            }
                            "grid" -> {
                                ContinueCard(recents.firstOrNull(), session) { detail = it }
                                Spacer(Modifier.height(sectionGap))
                                Text("All games", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold), color = Color.White)
                                Spacer(Modifier.height(10.dp))
                                PosterRow(GameCatalog.games.take(40), session, posterWidth) { detail = it }
                            }
                            else -> {
                                ContinueCard(recents.firstOrNull(), session) { detail = it }
                                Spacer(Modifier.height(sectionGap))
                                Text("Featured", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold), color = Color.White)
                                Spacer(Modifier.height(10.dp))
                                Row(
                                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                                ) {
                                    GameCatalog.featured.forEach { game ->
                                        FeaturedCard(
                                            game, session.isFavorite(game.id),
                                            onPlay = { session.playGame(game) },
                                            onFav = { session.toggleFavorite(game) },
                                            onOpen = { detail = game },
                                            width = featuredWidth,
                                            height = heroHeight
                                        )
                                    }
                                }
                                shelves.forEach { (title, games) ->
                                    Spacer(Modifier.height(sectionGap))
                                    Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 1)
                                    Spacer(Modifier.height(10.dp))
                                    PosterRow(games, session, posterWidth) { detail = it }
                                }
                            }
                        }
                        Spacer(Modifier.height(sectionGap))
                        Button(onClick = { filter = "Browse" }, modifier = Modifier.fillMaxWidth()) {
                            Text("Browse all games")
                        }
                    }
                    else -> {
                        Spacer(Modifier.height(sectionGap))
                        Text(filter, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = Color.White)
                        Spacer(Modifier.height(10.dp))
                        if (filteredGames.isEmpty()) {
                            Text(
                                when (filter) {
                                    "Favorites" -> "Star a game to pin it here."
                                    "Recents" -> "Launch a title and it will appear here."
                                    "For You", "Library" -> "Play or favorite games to fill this shelf."
                                    else -> "No titles in this filter."
                                },
                                color = Color(0xFFB0B0B8)
                            )
                        } else {
                            PosterRow(filteredGames, session, posterWidth) { detail = it }
                        }
                    }
                }
            }
            Spacer(Modifier.height(100.dp))
        }
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
                Column(horizontalAlignment = Alignment.End) {
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
private fun ContinueCard(last: CatalogGame?, session: SessionStore, onOpen: (CatalogGame) -> Unit) {
    if (last == null) return
    Text("Jump back in", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold), color = Color.White)
    Spacer(Modifier.height(10.dp))
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF16161E))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(64.dp, 84.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(accentColor(last.accent))
                .clickable { onOpen(last) }
        ) { Artwork(last, Modifier.fillMaxSize()) }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(last.title, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(last.tagline, color = Color(0xFFB0B0B8), style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(8.dp))
            Button(onClick = { session.playGame(last) }) { Text("Resume") }
        }
    }
}

@Composable
private fun ActivityStrip(session: SessionStore) {
    val activity = session.activity()
    val week = activity.format(activity.weekTotal())
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF16161E))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text("This week", color = Color.White, fontWeight = FontWeight.SemiBold)
            Text("$week streamed", color = Color(0xFFB0B0B8), style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun PosterRow(games: List<CatalogGame>, session: SessionStore, width: Dp, onOpen: (CatalogGame) -> Unit) {
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        games.forEach { game ->
            PosterCard(
                game,
                session.isFavorite(game.id),
                onOpen = { onOpen(game) },
                onPlay = { session.playGame(game) },
                onFav = { session.toggleFavorite(game) },
                width = width
            )
        }
    }
}

@Composable
private fun FeaturedCard(
    game: CatalogGame,
    favorite: Boolean,
    onPlay: () -> Unit,
    onFav: () -> Unit,
    onOpen: () -> Unit,
    width: Dp,
    height: Dp
) {
    Box(
        Modifier
            .width(width)
            .height(height)
            .clip(RoundedCornerShape(24.dp))
            .background(accentColor(game.accent))
            .clickable(onClick = onOpen)
    ) {
        Artwork(game, Modifier.fillMaxSize())
        Box(
            Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.78f))))
        )
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(game.provider, color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(game.title, color = Color.White, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(game.tagline, color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = onPlay) { Text("Play", maxLines = 1) }
                IconButton(onClick = onFav) {
                    Icon(if (favorite) Icons.Filled.Star else Icons.Outlined.StarBorder, contentDescription = "Favorite", tint = Color.White)
                }
            }
        }
    }
}

@Composable
private fun PosterCard(
    game: CatalogGame,
    favorite: Boolean,
    onOpen: () -> Unit,
    onPlay: () -> Unit,
    onFav: () -> Unit,
    width: Dp
) {
    Column(Modifier.width(width)) {
        Box(
            Modifier
                .size(width, width * 1.33f)
                .clip(RoundedCornerShape(16.dp))
                .background(accentColor(game.accent))
                .clickable(onClick = onOpen)
        ) {
            Artwork(game, Modifier.fillMaxSize())
            IconButton(
                onClick = onFav,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .background(Color.Black.copy(alpha = 0.35f), CircleShape)
            ) {
                Icon(if (favorite) Icons.Filled.Star else Icons.Outlined.StarBorder, contentDescription = "Favorite", tint = Color.White)
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(game.title, color = Color.White, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(game.provider, color = Color(0xFF808088), style = MaterialTheme.typography.labelSmall, maxLines = 1)
        TextButton(onClick = onPlay) { Text("Play") }
    }
}

@Composable
private fun Artwork(game: CatalogGame, modifier: Modifier = Modifier) {
    val url = ArtworkStore.urlFor(game)
    if (url != null) {
        AsyncImage(model = url, contentDescription = game.title, modifier = modifier, contentScale = ContentScale.Crop)
    } else {
        Box(modifier.background(accentColor(game.accent)), contentAlignment = Alignment.Center) {
            Text(game.title.take(1), color = Color.White, style = MaterialTheme.typography.headlineLarge)
        }
    }
}
