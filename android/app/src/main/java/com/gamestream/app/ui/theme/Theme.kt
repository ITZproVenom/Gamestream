package com.gamestream.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = Color(0xFF8B7CFF),
    onPrimary = Color.White,
    secondary = Color(0xFF6D5EFC),
    background = Color(0xFF0A0A12),
    surface = Color(0xFF14141A),
    onBackground = Color(0xFFF5F5F7),
    onSurface = Color(0xFFF5F5F7),
    surfaceVariant = Color(0xFF1C1C24),
    onSurfaceVariant = Color(0xFFB0B0B8)
)

@Composable
fun GameStreamTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColors,
        content = content
    )
}
