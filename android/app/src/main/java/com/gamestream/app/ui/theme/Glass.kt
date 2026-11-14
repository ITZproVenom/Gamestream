package com.gamestream.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.styropyr0.prismal.PrismalBackdrop
import com.styropyr0.prismal.PrismalGlassSurface
import com.styropyr0.prismal.shapes.PrismalRoundedRectangle

/**
 * The glass the app is drawn with.
 *
 * The backdrop is the thing the glass samples: what is behind the card. It
 * is captured once, where the background is drawn, and every card on the
 * screen reads from it, which is what makes the cards look like they are
 * sitting on the screen rather than painted on top of it.
 */
val LocalGlassBackdrop = staticCompositionLocalOf<PrismalBackdrop?> { null }

/** The accent every piece of the interface is tinted with. */
val LocalAccent = staticCompositionLocalOf<Accent> { Accent.Purple }

/** How the cards are finished. */
val LocalCardSurface = staticCompositionLocalOf<CardSurface> { CardSurface.Glass }

/** The corners, in the iOS app's sizes. */
object Radius {
    val card = 22.dp
    val tile = 18.dp
    val hero = 28.dp
    val chip = 999.dp
}

/**
 * A card of glass.
 *
 * The three finishes are the iOS app's: Glass is plain glass, Tinted
 * carries a wash of the accent, and Solid is an opaque panel for the
 * places where glass would only make the text harder to read.
 */
@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(Radius.card),
    onClick: (() -> Unit)? = null,
    contentPadding: PaddingValues = PaddingValues(18.dp),
    content: @Composable BoxScope.() -> Unit
) {
    val backdrop = LocalGlassBackdrop.current
    val accent = LocalAccent.current
    val surface = LocalCardSurface.current

    if (backdrop == null) {
        // Without a captured backdrop there is nothing to refract, so the
        // card is a plain panel rather than a broken one.
        Box(
            modifier = modifier
                .clip(shape)
                .background(Color(0xFF16161C).copy(alpha = if (surface == CardSurface.Solid) 1f else 0.86f))
                .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
                .padding(contentPadding)
        ) { content() }
        return
    }

    PrismalGlassSurface(
        backdrop = backdrop,
        modifier = modifier
            .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier),
        shape = { PrismalRoundedRectangle(22.dp) },
        tint = when (surface) {
            CardSurface.Tinted -> accent.color.copy(alpha = 0.18f)
            CardSurface.Glass -> Color.White.copy(alpha = 0.06f)
            CardSurface.Solid -> Color(0xFF14141A)
        },
        tintAlpha = 1f,
        blurRadius = 14.dp,
        saturation = 1.4f,
        chromaticAberration = 0.06f,
        refractionHeightPx = 14f,
        refractionAmountPx = 26f,
        depthEffect = true,
    ) {
        Box(modifier = Modifier.padding(contentPadding)) { content() }
    }
}

/** A round glass button, the app's icon buttons. */
@Composable
fun GlassIconButton(
    systemImage: ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    active: Boolean = false,
    onClick: () -> Unit
) {
    val backdrop = LocalGlassBackdrop.current
    val accent = LocalAccent.current
    val content: @Composable BoxScope.() -> Unit = {
        Icon(
            imageVector = systemImage,
            contentDescription = label,
            tint = if (active) accent.color else Color.White,
            modifier = Modifier.padding(12.dp)
        )
    }
    if (backdrop == null) {
        Box(
            modifier = modifier
                .clip(CircleShape)
                .background(Color(0xFF1E1E26))
                .clickable { onClick() },
            contentAlignment = Alignment.Center
        ) { content() }
        return
    }
    PrismalGlassSurface(
        backdrop = backdrop,
        modifier = modifier.clickable { onClick() },
        shape = { PrismalRoundedRectangle(999.dp) },
        tint = if (active) accent.color.copy(alpha = 0.22f) else Color.White.copy(alpha = 0.08f),
        tintAlpha = 1f,
        blurRadius = 10.dp,
        saturation = 1.3f,
        chromaticAberration = 0.04f,
        depthEffect = true,
    ) { content() }
}

/** A capsule of glass, used for the labels and the filters. */
@Composable
fun GlassChip(
    title: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val backdrop = LocalGlassBackdrop.current
    val accent = LocalAccent.current
    val label: @Composable BoxScope.() -> Unit = {
        Text(
            text = title,
            color = if (selected) Color.White else Color.White.copy(alpha = 0.72f),
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp)
        )
    }
    if (backdrop == null) {
        Box(
            modifier = modifier
                .clip(RoundedCornerShape(Radius.chip))
                .background(if (selected) accent.color.copy(alpha = 0.3f) else Color(0xFF1A1A22))
                .clickable { onClick() }
        ) { label() }
        return
    }
    PrismalGlassSurface(
        backdrop = backdrop,
        modifier = modifier.clickable { onClick() },
        shape = { PrismalRoundedRectangle(999.dp) },
        tint = if (selected) accent.color.copy(alpha = 0.26f) else Color.White.copy(alpha = 0.06f),
        tintAlpha = 1f,
        blurRadius = 10.dp,
        saturation = 1.3f,
        depthEffect = true,
    ) { label() }
}
