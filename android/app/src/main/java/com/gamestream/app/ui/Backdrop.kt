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
import com.gamestream.app.ui.theme.Backdrop
import com.gamestream.app.ui.theme.backdropFor

/**
 * The backdrop behind the app.
 *
 * The seven backdrops are the iOS app's, each one a deep base colour with
 * two pools of the accent colour drifting over it. The motion setting
 * decides whether they drift at all, and the "still" choice holds them
 * exactly where they are.
 */
@Composable
fun GameStreamBackdrop(appearance: AppearancePrefs, modifier: Modifier = Modifier) {
    val name = appearance.background
    val solid = name.equals("solid", true) || name.equals("customColor", true)
    val backdrop: Backdrop = if (solid) backdropFor("midnight") else backdropFor(name)
    val accent = backdrop.glow
    val base = backdrop.base
    val animated = appearance.animation == "full" && !solid
    val strength = (1f - appearance.backgroundDim).coerceIn(0.08f, 0.9f)

    val drift by if (animated) {
        rememberInfiniteTransition(label = "backdrop").animateFloat(
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
        val width = size.width
        val height = size.height
        if (width <= 0f || height <= 0f) return@Canvas

        // Two pools of colour over the base, drifting apart and back: the
        // same shape as the iOS mesh, which is what the glass refracts.
        val first = Offset(
            x = width * (0.24f + 0.42f * drift),
            y = height * (0.16f + 0.10f * drift)
        )
        val second = Offset(
            x = width * (0.76f - 0.42f * drift),
            y = height * (0.72f - 0.08f * drift)
        )
        drawRect(
            brush = Brush.radialGradient(
                colors = listOf(
                    accent.copy(alpha = 0.42f * strength),
                    backdrop.secondary.copy(alpha = 0f)
                ),
                center = first,
                radius = width * 1.05f
            )
        )
        drawRect(
            brush = Brush.radialGradient(
                colors = listOf(
                    backdrop.secondary.copy(alpha = 0.30f * strength),
                    accent.copy(alpha = 0f)
                ),
                center = second,
                radius = width * 1.15f
            )
        )
    }
}
