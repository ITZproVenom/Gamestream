package com.gamestream.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * The accents the app offers, the same nine the iOS app has.
 *
 * The Android app used to have a different set under different names, so
 * choosing "rose" or "cyan" on one platform and "pink" on the other left the
 * two looking nothing alike. These are the iOS names and the iOS colours.
 */
enum class Accent(val title: String, val color: Color) {
    Purple("Purple", Color(0xFF8B7CFF)),
    Blue("Blue", Color(0xFF4A94FF)),
    Green("Green", Color(0xFF2ED9A0)),
    Orange("Orange", Color(0xFFF5C04A)),
    Pink("Pink", Color(0xFFFF7AA8)),
    Cyan("Cyan", Color(0xFF3FD2E0)),
    Teal("Teal", Color(0xFF14B8A6)),
    Gold("Gold", Color(0xFFD4AF37)),
    Red("Red", Color(0xFFF2476B)),
}

/**
 * The backdrops the app offers, the same seven the iOS app has.
 *
 * Each one is a base colour and two pools of the accent colour, which is
 * how the iOS mesh is built: a deep tone, the accent twice at different
 * strengths, and the base showing through.
 */
enum class Backdrop(val title: String, val base: Color, val glow: Color, val secondary: Color) {
    Aurora("Aurora", Color(0xFF07070F), Color(0xFF8B7CFF), Color(0xFF3FD2E0)),
    Midnight("Midnight", Color(0xFF03040C), Color(0xFF2B4CFF), Color(0xFF8B7CFF)),
    Ocean("Ocean", Color(0xFF04121C), Color(0xFF00A6C8), Color(0xFF1E4C8A)),
    Sunset("Sunset", Color(0xFF160A12), Color(0xFFFF6B57), Color(0xFFFFB347)),
    Forest("Forest", Color(0xFF05130D), Color(0xFF2ED9A0), Color(0xFF0E7C5A)),
    RoseGold("Rose Gold", Color(0xFF160C10), Color(0xFFFF9A8B), Color(0xFFE8B4B8)),
    Monochrome("Monochrome", Color(0xFF08080A), Color(0xFFBFC2CC), Color(0xFF6E7078)),
}

/** How the cards are finished. The iOS app calls them Glass, Tinted and Solid. */
enum class CardSurface(val title: String) {
    Glass("Glass"),
    Tinted("Tinted"),
    Solid("Solid"),
}

/** The accent the app is using, by the name the settings store. */
fun accentFor(name: String): Accent =
    Accent.entries.firstOrNull { it.title.equals(name, ignoreCase = true) }
        ?: Accent.entries.firstOrNull { it.name.equals(name, ignoreCase = true) }
        ?: Accent.Purple

/** The backdrop the app is using, by the name the settings store. */
fun backdropFor(name: String): Backdrop =
    Backdrop.entries.firstOrNull { it.title.equals(name, ignoreCase = true) }
        ?: Backdrop.entries.firstOrNull { it.name.equals(name, ignoreCase = true) }
        ?: Backdrop.Aurora

/** The card finish the app is using, by the name the settings store. */
fun cardSurfaceFor(name: String): CardSurface =
    CardSurface.entries.firstOrNull { it.title.equals(name, ignoreCase = true) }
        ?: CardSurface.entries.firstOrNull { it.name.equals(name, ignoreCase = true) }
        ?: CardSurface.Glass
