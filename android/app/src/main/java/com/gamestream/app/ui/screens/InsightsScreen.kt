package com.gamestream.app.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.gamestream.app.GameCatalog
import com.gamestream.app.PlayActivity
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.theme.GlassCard
import com.gamestream.app.ui.theme.LocalAccent
import java.util.Calendar

/**
 * Insights: what the sessions add up to.
 *
 * The Android app has recorded every session for months and never shown
 * any of it. This is the iOS screen: the totals, the week as a chart, and
 * the games that took the most time.
 */
@Composable
fun InsightsScreen(session: SessionStore) {
    val context = LocalContext.current
    val activity = PlayActivity.get(context)
    val accent = LocalAccent.current
    val ranked = activity.rankedThisWeek().take(8)
    val week = activity.weekByDay()

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 28.dp)
    ) {
        Spacer(Modifier.height(12.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
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
        }

        Spacer(Modifier.height(12.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatCard(
                value = activity.format(activity.totalSeconds()),
                caption = "Total playtime",
                modifier = Modifier.weight(1f)
            )
            StatCard(
                value = "${ranked.size}",
                caption = "Games this week",
                modifier = Modifier.weight(1f)
            )
        }

        Spacer(Modifier.height(18.dp))

        GlassCard(contentPadding = PaddingValues(18.dp)) {
            Column {
                Text(
                    text = "This week",
                    color = Color.White,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(12.dp))
                WeekChart(week, accent.color)
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    for ((label, _) in week) {
                        Text(
                            text = label,
                            color = Color.White.copy(alpha = 0.55f),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
            }
        }

        if (ranked.isNotEmpty()) {
            Spacer(Modifier.height(18.dp))
            Text(
                text = "Most played",
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(10.dp))
            for (stat in ranked) {
                val game = GameCatalog.find(stat.id)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        Modifier
                            .size(width = 38.dp, height = 51.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF1E1E28))
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            text = stat.title.ifBlank { game?.title ?: stat.id },
                            color = Color.White,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "${stat.sessionCount} session${if (stat.sessionCount == 1) "" else "s"}",
                            color = Color.White.copy(alpha = 0.6f),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                    Text(
                        text = activity.format(stat.weekSeconds),
                        color = accent.color,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        } else {
            Spacer(Modifier.height(18.dp))
            GlassCard {
                Text(
                    text = "Nothing to chart yet. Play a game for more than a quarter of a minute and it will start showing up here.",
                    color = Color.White.copy(alpha = 0.75f),
                    style = MaterialTheme.typography.bodyMedium
                )
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

/** The last seven days, as a bar each. */
@Composable
private fun WeekChart(week: List<Pair<String, Long>>, accent: Color) {
    val peak = week.maxOfOrNull { it.second } ?: 0L
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(120.dp)
    ) {
        if (peak <= 0L) return@Canvas
        val slot = size.width / week.size.coerceAtLeast(1)
        val barWidth = slot * 0.46f
        for ((index, entry) in week.withIndex()) {
            val value = entry.second.toFloat()
            val fraction = (value / peak.toFloat()).coerceIn(0.02f, 1f)
            val height = size.height * fraction
            val x = slot * index + (slot - barWidth) / 2f
            val top = size.height - height
            drawRoundRect(
                color = accent.copy(alpha = 0.85f),
                topLeft = Offset(x, top),
                size = Size(barWidth, height),
                cornerRadius = CornerRadius(10f, 10f)
            )
        }
    }
}
