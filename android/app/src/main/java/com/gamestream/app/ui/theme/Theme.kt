package com.gamestream.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.gamestream.app.AppearancePrefs

/**
 * The colours of the app.
 *
 * The accents are the iOS app's nine and the backdrops are its seven, so
 * the two apps look like the same product. The old Android names - emerald,
 * azure, gold, crimson - are still understood, so an existing choice is not
 * thrown away.
 */
fun accentColor(name: String): Color = accentFor(name).color

@Composable
fun GameStreamTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val appearance = remember { AppearancePrefs(context) }
    // Read so a change in Settings re-themes the app immediately. These are
    // plain preference reads, so without the shared revision the accent and
    // the light or dark choice only took effect after a restart.
    @Suppress("UNUSED_VARIABLE")
    val revision = appearance.revision
    val dark = when (appearance.mode) {
        "light" -> false
        "system" -> isSystemInDarkTheme()
        else -> true
    }
    val accent = accentFor(appearance.accent)
    val primary = accent.color
    val scheme = if (dark) {
        darkColorScheme(
            primary = primary,
            onPrimary = Color.White,
            secondary = primary.copy(alpha = 0.8f),
            background = Color(0xFF0A0A12),
            surface = Color(0xFF14141A),
            onBackground = Color(0xFFF5F5F7),
            onSurface = Color(0xFFF5F5F7),
            surfaceVariant = Color(0xFF1C1C24),
            onSurfaceVariant = Color(0xFFB0B0B8)
        )
    } else {
        lightColorScheme(
            primary = primary,
            onPrimary = Color.White,
            background = Color(0xFFF4F4F8),
            surface = Color.White,
            onBackground = Color(0xFF121218),
            onSurface = Color(0xFF121218)
        )
    }
    CompositionLocalProvider(
        LocalAccent provides accent,
        LocalCardSurface provides cardSurfaceFor(appearance.cardStyle)
    ) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
