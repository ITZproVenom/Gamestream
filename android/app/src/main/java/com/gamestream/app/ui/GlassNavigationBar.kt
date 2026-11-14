package com.gamestream.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.gamestream.app.ui.theme.LocalAccent
import com.styropyr0.prismal.PrismalBackdrop
import com.styropyr0.prismal.PrismalGlassSurface
import com.styropyr0.prismal.shapes.PrismalRoundedRectangle

/**
 * The bar along the bottom, made of glass.
 *
 * The iOS app has five tabs: Home, Library, Search, Insights and
 * Settings. The Android app had three, and the first thing on the screen
 * was a list rather than a home.
 */
@Composable
fun GlassNavigationBar(
    selected: Tab,
    onSelect: (Tab) -> Unit,
    backdrop: PrismalBackdrop,
    modifier: Modifier = Modifier
) {
    val accent = LocalAccent.current
    val items = listOf(
        Tab.Home to Icons.Default.Home,
        Tab.Library to Icons.Default.GridView,
        Tab.Search to Icons.Default.Search,
        Tab.Insights to Icons.Default.Insights,
        Tab.Settings to Icons.Default.Settings
    )

    Box(modifier.fillMaxWidth()) {
        PrismalGlassSurface(
            backdrop = backdrop,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp),
            shape = { PrismalRoundedRectangle(999.dp) },
            tint = Color.White.copy(alpha = 0.08f),
            tintAlpha = 1f,
            blurRadius = 14.dp,
            saturation = 1.4f,
            chromaticAberration = 0.05f,
            depthEffect = true,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 6.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                for ((tab, icon) in items) {
                    NavigationItem(
                        tab = tab,
                        icon = icon,
                        selected = tab == selected,
                        accent = accent.color,
                        onClick = { onSelect(tab) },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun NavigationItem(
    tab: Tab,
    icon: ImageVector,
    selected: Boolean,
    accent: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clickable { onClick() }
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = icon,
            contentDescription = tab.label,
            tint = if (selected) accent else Color.White.copy(alpha = 0.62f),
            modifier = Modifier.size(22.dp)
        )
        Spacer(Modifier.height(3.dp))
        Text(
            text = tab.label,
            color = if (selected) Color.White else Color.White.copy(alpha = 0.62f),
            style = MaterialTheme.typography.labelSmall
        )
    }
}
