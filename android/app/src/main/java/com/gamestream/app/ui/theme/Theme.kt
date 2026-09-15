package com.gamestream.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.gamestream.app.AppearancePrefs

private fun accentColor(name: String): Color = when (name) {
    "green", "emerald" -> Color(0xFF2ED9A0)
    "blue", "azure" -> Color(0xFF4A94FF)
    "orange", "gold" -> Color(0xFFF5C04A)
    "crimson" -> Color(0xFFF2476B)
    else -> Color(0xFF8B7CFF)
}

@Composable
fun GameStreamTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val appearance = remember { AppearancePrefs(context) }
    val dark = when (appearance.mode) {
        "light" -> false
        "system" -> isSystemInDarkTheme()
        else -> true
    }
    val primary = accentColor(appearance.accent)
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
    MaterialTheme(colorScheme = scheme, content = content)
}
