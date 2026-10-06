package com.gamestream.app.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.gamestream.app.AppearancePrefs
import com.gamestream.app.ui.theme.accentColor

/**
 * The backdrop behind the hub.
 *
 * The background setting offered Aurora, Still and Mesh and every one of them
 * drew the same flat colour, because nothing in the app ever read the style
 * beyond looking up a solid value. These are the gradients those names
 * promised: two soft pools of the accent colour over the base, drifting when
 * the motion setting allows it and holding still when it does not.
 */
@Composable
fun GameStreamBackdrop(appearance: AppearancePrefs, modifier: Modifier = Modifier) {
    val base = Color(appearance.backgroundColorArgb())
    val accent = accentColor(appearance.accent)
    val style = appearance.background
    val animated = style == "aurora" && appearance.animation == "full"
    val strength = (1f - appearance.backgroundDim).coerceIn(0.08f, 0.9f)

    val drift by if (animated) {
        rememberInfiniteTransition(label = "aurora").animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 16000, easing = LinearEasing),
                repeatMode = RepeatMode.Reverse
            ),
            label = "drift"
        )
    } else {
        androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(0.5f) }
    }

    Canvas(modifier.fillMaxSize()) {
        drawRect(color = base)
        if (style == "solid" || style == "customColor") return@Canvas

        val width = size.width
        val height = size.height
        if (width <= 0f || height <= 0f) return@Canvas

        if (style == "mesh") {
            // A fixed weave rather than a drift: four corners of accent over
            // the base, which is what "mesh" was always meant to look like.
            drawRect(
                brush = Brush.linearGradient(
                    colors = listOf(
                        accent.copy(alpha = 0.34f * strength),
                        base.copy(alpha = 0f),
                        accent.copy(alpha = 0.22f * strength)
                    ),
                    start = Offset(0f, 0f),
                    end = Offset(width, height)
                )
            )
            drawRect(
                brush = Brush.linearGradient(
                    colors = listOf(
                        accent.copy(alpha = 0.20f * strength),
                        base.copy(alpha = 0f)
                    ),
                    start = Offset(width, 0f),
                    end = Offset(0f, height)
                )
            )
            return@Canvas
        }

        val top = Offset(width * (0.22f + 0.46f * drift), height * 0.14f)
        val bottom = Offset(width * (0.78f - 0.46f * drift), height * 0.74f)
        drawRect(
            brush = Brush.radialGradient(
                colors = listOf(accent.copy(alpha = 0.40f * strength), base.copy(alpha = 0f)),
                center = top,
                radius = width * 0.95f
            )
        )
        drawRect(
            brush = Brush.radialGradient(
                colors = listOf(accent.copy(alpha = 0.26f * strength), base.copy(alpha = 0f)),
                center = bottom,
                radius = width * 1.1f
            )
        )
    }
}
