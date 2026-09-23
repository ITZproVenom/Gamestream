package com.gamestream.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import coil.compose.AsyncImage
import com.gamestream.app.AppearancePrefs
import com.gamestream.app.ArtworkStore
import com.gamestream.app.CatalogGame
import com.gamestream.app.ForYouCatalog
import com.gamestream.app.GameCatalog
import com.gamestream.app.GameDiscovery
import com.gamestream.app.SessionStore

@Composable
fun GameHub(session: SessionStore, modifier: Modifier = Modifier) {
    val appearance = AppearancePrefs.get(LocalContext.current)
    val rev = appearance.revision

    var filter by remember { mutableStateOf("Home") }
    var detail by remember { mutableStateOf<CatalogGame?>(null) }

    val recents = session.recentGames()
    val favs = session.favoriteGames()
    val forYou = remember(session.favoriteIds, session.recentIds) { ForYouCatalog.forYou(favs, recents) }
    val because = remember(session.recentIds) { ForYouCatalog.becauseYouPlayed(recents) }

    val hubLayout = appearance.hubLayout
    val showGenres = appearance.showGenreFilters
    val showActivity = appearance.showActivityOnHome
    val posterW = appearance.posterWidthDp().dp
    val heroH = appearance.heroHeightDp().dp
    val sectionGap = appearance.sectionSpacingDp().dp

    val primaryChips = listOf("Home", "Library", "Browse", "For You", "Favorites", "Recents")
    val genreChips = if (showGenres) {
        GameDiscovery.shelves().map { it.first }.take(12)
    } else emptyList()

    val filtered = when (filter) {
        "For You" -> forYou
        "Favorites" -> favs
        "Recents" -> recents
        "Library" -> (favs + recents).distinctBy { it.id }
        "Browse", "Home" -> GameCatalog.games
        else -> GameDiscovery.fromTitle(filter)?.let { GameDiscovery.games(it) }
            ?: GameCatalog.games.filter { it.genre.equals(filter, ignoreCase = true) }
    }

    val bg = Color(appearance.backgroundColorArgb())
    @Suppress("UNUSED_VARIABLE")
    val forceLayout = rev to hubLayout

    Box(modifier.fillMaxSize().background(bg)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 96.dp)
        ) {
            item {
                Column(Modifier.padding(horizontal = 20.dp, vertical = 16.dp)) {
                    Text(
                        "GameStream",
                        style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
                        color = Color.White,
                        maxLines = 1
                    )
                    Text(
                        "Xbox Cloud Gaming",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color(0xFFA0A0AA)
                    )
                }
            }

            item {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    primaryChips.forEach { chip ->
                        FilterChip(
                            selected = filter == chip,
                            onClick = { filter = chip },
                            label = { Text(chip, maxLines = 1) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.28f),
                                selectedLabelColor = Color.White,
                                labelColor = Color(0xFFC8C8D0)
                            )
                        )
                    }
                }
                if (genreChips.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        genreChips.forEach { chip ->
                            FilterChip(
                                selected = filter == chip,
                                onClick = { filter = chip },
                                label = { Text(chip, maxLines = 1) },
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f),
                                    selectedLabelColor = Color.White,
                                    labelColor = Color(0xFFA8A8B0)
                                )
                            )
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
            }

            if (filter == "Home") {
                if (showActivity) {
                    item {
                        ActivityStrip(session, Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
                    }
                }

                when (hubLayout) {
                    "grid" -> {
                        recents.firstOrNull()?.let { last ->
                            item {
                                JumpBackInCard(
                                    game = last,
                                    onResume = { session.playGame(last) },
                                    onOpen = { detail = last },
                                    modifier = Modifier.padding(horizontal = 20.dp, vertical = sectionGap / 2)
                                )
                            }
                        }
                        item { ShelfHeader("All games") }
                        item {
                            PosterStrip(
                                games = GameCatalog.games.take(48),
                                posterWidth = posterW,
                                isFavorite = { session.isFavorite(it) },
                                onOpen = { detail = it },
                                onPlay = { session.playGame(it) },
                                onFav = { session.toggleFavorite(it) }
                            )
                        }
                    }
                    "rails" -> {
                        recents.firstOrNull()?.let { last ->
                            item {
                                JumpBackInCard(
                                    game = last,
                                    onResume = { session.playGame(last) },
                                    onOpen = { detail = last },
                                    modifier = Modifier.padding(horizontal = 20.dp, vertical = sectionGap / 2)
                                )
                            }
                        }
                        item { ShelfHeader("Featured") }
                        item {
                            PosterStrip(
                                games = GameCatalog.featured.ifEmpty { GameCatalog.games.take(8) },
                                posterWidth = posterW,
                                isFavorite = { session.isFavorite(it) },
                                onOpen = { detail = it },
                                onPlay = { session.playGame(it) },
                                onFav = { session.toggleFavorite(it) }
                            )
                        }
                        homeShelves(session, recents, favs, forYou, because).forEach { (title, games) ->
                            item { ShelfHeader(title) }
                            item {
                                PosterStrip(
                                    games = games,
                                    posterWidth = posterW,
                                    isFavorite = { session.isFavorite(it) },
                                    onOpen = { detail = it },
                                    onPlay = { session.playGame(it) },
                                    onFav = { session.toggleFavorite(it) }
                                )
                            }
                        }
                    }
                    else -> { // editorial
                        recents.firstOrNull()?.let { last ->
                            item {
                                JumpBackInCard(
                                    game = last,
                                    onResume = { session.playGame(last) },
                                    onOpen = { detail = last },
                                    modifier = Modifier.padding(horizontal = 20.dp, vertical = sectionGap / 2)
                                )
                            }
                        }
                        GameCatalog.featured.firstOrNull()?.let { hero ->
                            item {
                                HeroCard(
                                    game = hero,
                                    favorite = session.isFavorite(hero.id),
                                    height = heroH,
                                    onPlay = { session.playGame(hero) },
                                    onFav = { session.toggleFavorite(hero) },
                                    onOpen = { detail = hero },
                                    modifier = Modifier
                                        .padding(horizontal = 20.dp, vertical = sectionGap / 2)
                                        .fillMaxWidth()
                                )
                            }
                        }
                        homeShelves(session, recents, favs, forYou, because).forEach { (title, games) ->
                            item { ShelfHeader(title) }
                            item {
                                PosterStrip(
                                    games = games,
                                    posterWidth = posterW,
                                    isFavorite = { session.isFavorite(it) },
                                    onOpen = { detail = it },
                                    onPlay = { session.playGame(it) },
                                    onFav = { session.toggleFavorite(it) }
                                )
                            }
                        }
                    }
                }

                item {
                    Button(
                        onClick = { filter = "Browse" },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 16.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                    ) {
                        Text("Browse all games")
                    }
                }
            } else {
                item {
                    Text(
                        filter,
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                        color = Color.White,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
                    )
                }
                if (filtered.isEmpty()) {
                    item {
                        Text(
                            emptyCopy(filter),
                            color = Color(0xFFA0A0AA),
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                        )
                    }
                } else {
                    item {
                        PosterStrip(
                            games = filtered,
                            posterWidth = posterW,
                            isFavorite = { session.isFavorite(it) },
                            onOpen = { detail = it },
                            onPlay = { session.playGame(it) },
                            onFav = { session.toggleFavorite(it) }
                        )
                    }
                }
            }
        }

        detail?.let { game ->
            GameDetailDialog(
                game = game,
                favorite = session.isFavorite(game.id),
                queued = session.isQueued(game.id),
                onDismiss = { detail = null },
                onPlay = { session.playGame(game); detail = null },
                onFav = { session.toggleFavorite(game) },
                onQueue = { session.toggleQueue(game) }
            )
        }
    }
}

private fun homeShelves(
    session: SessionStore,
    recents: List<CatalogGame>,
    favs: List<CatalogGame>,
    forYou: List<CatalogGame>,
    because: List<Pair<String, List<CatalogGame>>>
): List<Pair<String, List<CatalogGame>>> = buildList {
    val queued = session.queuedGames()
    if (queued.isNotEmpty()) add("Up Next" to queued)
    if (recents.isNotEmpty()) add("Continue playing" to recents)
    if (favs.isNotEmpty()) add("Favorites" to favs)
    if (forYou.isNotEmpty()) add("For You" to forYou)
    because.forEach { add(it) }
    add("Popular on Cloud" to GameCatalog.games.take(12))
    addAll(GameDiscovery.shelves())
}

private fun emptyCopy(filter: String): String = when (filter) {
    "Favorites" -> "Star a game to pin it here."
    "Recents" -> "Launch a title and it will appear here."
    "For You", "Library" -> "Play or favorite games to fill this shelf."
    else -> "No titles in this filter."
}

@Composable
private fun ShelfHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
        color = Color.White,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 10.dp)
    )
}

@Composable
private fun ActivityStrip(session: SessionStore, modifier: Modifier = Modifier) {
    val activity = session.activity()
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = Color(0xFF16161E),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(Modifier.padding(14.dp)) {
            Text("This week", color = Color.White, fontWeight = FontWeight.SemiBold)
            Text(
                "${activity.format(activity.weekTotal())} streamed",
                color = Color(0xFFA0A0AA),
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

@Composable
private fun JumpBackInCard(
    game: CatalogGame,
    onResume: () -> Unit,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier) {
        Text(
            "Jump back in",
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
            color = Color.White
        )
        Spacer(Modifier.height(10.dp))
        Surface(
            shape = RoundedCornerShape(18.dp),
            color = Color(0xFF16161E),
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                Modifier.padding(14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier
                        .size(64.dp, 84.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(game.accent.toInt()))
                        .clickable(onClick = onOpen)
                ) {
                    GameArt(game, Modifier.fillMaxSize())
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        game.title,
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        game.tagline,
                        color = Color(0xFFA0A0AA),
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = onResume) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text("  Resume")
                    }
                }
            }
        }
    }
}

@Composable
private fun HeroCard(
    game: CatalogGame,
    favorite: Boolean,
    height: Dp,
    onPlay: () -> Unit,
    onFav: () -> Unit,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(22.dp))
            .background(Color(game.accent.toInt()))
            .clickable(onClick = onOpen)
    ) {
        GameArt(game, Modifier.fillMaxSize())
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.82f))
                    )
                )
        )
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                game.title,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.titleLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                game.tagline,
                color = Color(0xFFD0D0D8),
                style = MaterialTheme.typography.bodySmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(10.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = onPlay,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text("  Play")
                }
                IconButton(
                    onClick = onFav,
                    modifier = Modifier
                        .size(40.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.White.copy(alpha = 0.15f))
                ) {
                    Icon(
                        if (favorite) Icons.Default.Favorite else Icons.Outlined.FavoriteBorder,
                        contentDescription = "Favorite",
                        tint = if (favorite) Color(0xFFFF6B8A) else Color.White
                    )
                }
            }
        }
    }
}

@Composable
private fun PosterStrip(
    games: List<CatalogGame>,
    posterWidth: Dp,
    isFavorite: (String) -> Boolean,
    onOpen: (CatalogGame) -> Unit,
    onPlay: (CatalogGame) -> Unit,
    onFav: (CatalogGame) -> Unit
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        items(games, key = { it.id }) { game ->
            PosterCard(
                game = game,
                width = posterWidth,
                favorite = isFavorite(game.id),
                onOpen = { onOpen(game) },
                onPlay = { onPlay(game) },
                onFav = { onFav(game) }
            )
        }
    }
}

@Composable
private fun PosterCard(
    game: CatalogGame,
    width: Dp,
    favorite: Boolean,
    onOpen: () -> Unit,
    onPlay: () -> Unit,
    onFav: () -> Unit
) {
    Column(
        Modifier
            .width(width)
            .clickable(onClick = onOpen)
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(3f / 4f)
                .clip(RoundedCornerShape(14.dp))
                .background(Color(game.accent.toInt()))
        ) {
            GameArt(game, Modifier.fillMaxSize())
            IconButton(
                onClick = onFav,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(4.dp)
                    .size(32.dp)
            ) {
                Icon(
                    if (favorite) Icons.Default.Favorite else Icons.Outlined.FavoriteBorder,
                    contentDescription = null,
                    tint = if (favorite) Color(0xFFFF6B8A) else Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.45f))
                    .clickable(onClick = onPlay)
                    .padding(vertical = 6.dp),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.PlayArrow, contentDescription = "Play", tint = Color.White, modifier = Modifier.size(20.dp))
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            game.title,
            color = Color.White,
            style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun GameArt(game: CatalogGame, modifier: Modifier = Modifier) {
    val url = game.posterUrl ?: ArtworkStore.url(game.id)
    AsyncImage(
        model = url,
        contentDescription = game.title,
        contentScale = ContentScale.Crop,
        modifier = modifier
    )
}

@Composable
private fun GameDetailDialog(
    game: CatalogGame,
    favorite: Boolean,
    queued: Boolean,
    onDismiss: () -> Unit,
    onPlay: () -> Unit,
    onFav: () -> Unit,
    onQueue: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = Color(0xFF16161E),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(Modifier.padding(20.dp)) {
                Text(
                    game.title,
                    color = Color.White,
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(8.dp))
                Text(game.tagline, color = Color(0xFFA0A0AA), maxLines = 3, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(4.dp))
                Text("${game.genre} · ${game.provider}", color = Color(0xFF808088), style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(16.dp))
                Button(onClick = onPlay, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Text("  Play now")
                }
                Spacer(Modifier.height(8.dp))
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    TextButton(onClick = onFav) {
                        Text(if (favorite) "Unfavorite" else "Favorite")
                    }
                    TextButton(onClick = onQueue) {
                        Text(if (queued) "Queued" else "Up Next")
                    }
                    TextButton(onClick = onDismiss) {
                        Text("Close")
                    }
                }
            }
        }
    }
}
