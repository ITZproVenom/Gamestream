package com.gamestream.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.gamestream.app.AppearancePrefs
import com.gamestream.app.BetterXCloudInjector
import com.gamestream.app.CloudCatalogService
import com.gamestream.app.OnboardingPrefs
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.screens.HomeScreen
import com.gamestream.app.ui.screens.InsightsScreen
import com.gamestream.app.ui.screens.IntroScreen
import com.gamestream.app.ui.screens.LibraryScreen
import com.gamestream.app.ui.screens.SearchScreen
import com.gamestream.app.ui.screens.SettingsScreen
import com.gamestream.app.ui.screens.WelcomeScreen
import com.gamestream.app.ui.theme.GameStreamTheme
import com.gamestream.app.ui.theme.LocalAccent
import com.gamestream.app.ui.theme.LocalCardSurface
import com.gamestream.app.ui.theme.LocalGlassBackdrop
import com.gamestream.app.ui.theme.accentFor
import com.gamestream.app.ui.theme.cardSurfaceFor
import com.styropyr0.prismal.sources.prismalGlassLayer
import com.styropyr0.prismal.sources.rememberPrismalGlassLayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The five tabs, the same ones the iOS app has. */
enum class Tab(val label: String) {
    Home("Home"), Library("Library"), Search("Search"), Insights("Insights"), Settings("Settings")
}

@Composable
fun GameStreamApp(session: SessionStore = viewModel()) {
    var tab by remember { mutableStateOf(Tab.Home) }
    val context = LocalContext.current
    var introCompleted by remember { mutableStateOf(OnboardingPrefs.isIntroDone(context)) }
    val appearance = remember { AppearancePrefs(context) }
    @Suppress("UNUSED_VARIABLE")
    val rev = appearance.revision

    LaunchedEffect(Unit) {
        CloudCatalogService.fetchAndInstall(context.applicationContext)
        withContext(Dispatchers.IO) {
            BetterXCloudInjector.ensureFetched(context.applicationContext)
        }
    }

    LaunchedEffect(session.isSignedIn) {
        if (session.isSignedIn) session.consumeLaunchResumeIfNeeded()
    }

    LaunchedEffect(session.requestedTab) {
        when (session.requestedTab) {
            "library" -> tab = Tab.Library
            "search" -> tab = Tab.Search
            "settings" -> tab = Tab.Settings
            "home" -> tab = Tab.Home
            "insights" -> tab = Tab.Insights
        }
        session.requestedTab = null
    }

    if (!introCompleted) {
        IntroScreen { introCompleted = true }
        return
    }

    if (!session.isSignedIn) {
        WelcomeScreen(session)
        return
    }

    GameStreamTheme {
        // The glass samples what is behind it, so the background is captured
        // once here and every card on the screen reads from it.
        val backdrop = rememberPrismalGlassLayer()

        CompositionLocalProvider(
            LocalGlassBackdrop provides backdrop,
            LocalAccent provides accentFor(appearance.accent),
            LocalCardSurface provides cardSurfaceFor(appearance.cardStyle)
        ) {
            Scaffold(
                containerColor = Color.Transparent,
                bottomBar = {
                    AnimatedVisibility(visible = !session.isStreaming) {
                        GlassNavigationBar(
                            selected = tab,
                            onSelect = { tab = it },
                            backdrop = backdrop
                        )
                    }
                }
            ) { padding ->
                Box(
                    Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .prismalGlassLayer(backdrop)
                ) {
                    GameStreamBackdrop(appearance)
                    when (tab) {
                        Tab.Home -> HomeScreen(session)
                        Tab.Library -> LibraryScreen(session)
                        Tab.Search -> SearchScreen(session)
                        Tab.Insights -> InsightsScreen(session)
                        Tab.Settings -> SettingsScreen(session)
                    }
                }
            }
        }
    }
}
