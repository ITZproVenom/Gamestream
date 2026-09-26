package com.gamestream.app.ui

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.gamestream.app.AppearancePrefs
import com.gamestream.app.BetterXCloudInjector
import com.gamestream.app.CloudCatalogService
import com.gamestream.app.OnboardingPrefs
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.screens.IntroScreen
import com.gamestream.app.ui.screens.LibraryScreen
import com.gamestream.app.ui.screens.SearchScreen
import com.gamestream.app.ui.screens.SettingsScreen
import com.gamestream.app.ui.screens.WelcomeScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class Tab(val label: String) {
    Library("Library"), Search("Search"), Settings("Settings")
}

@Composable
fun GameStreamApp(session: SessionStore = viewModel()) {
    val context = LocalContext.current
    val appearance = AppearancePrefs.get(context)
    // Recompose when any appearance setting changes
    @Suppress("UNUSED_VARIABLE")
    val appearanceRev = appearance.revision

    val tabPrefs = remember { context.getSharedPreferences("gamestream.ui", Context.MODE_PRIVATE) }
    var tab by remember {
        mutableStateOf(
            when (tabPrefs.getString("selectedTab", Tab.Library.name)) {
                Tab.Search.name -> Tab.Search
                Tab.Settings.name -> Tab.Settings
                else -> Tab.Library
            }
        )
    }
    var introCompleted by remember { mutableStateOf(OnboardingPrefs.isIntroDone(context)) }
    var showOpening by remember { mutableStateOf(true) }
    val bgColor = MaterialTheme.colorScheme.background

    LaunchedEffect(Unit) {
        CloudCatalogService.refreshIfNeeded(context.applicationContext)
        withContext(Dispatchers.IO) {
            BetterXCloudInjector.ensureFetched(context.applicationContext)
        }
    }

    LaunchedEffect(session.isSignedIn) {
        if (session.isSignedIn) session.consumeLaunchResumeIfNeeded()
    }

    LaunchedEffect(session.requestedTab) {
        val next = when (session.requestedTab) {
            "library" -> Tab.Library
            "search" -> Tab.Search
            "settings" -> Tab.Settings
            else -> null
        }
        if (next != null) {
            tab = next
            tabPrefs.edit().putString("selectedTab", next.name).apply()
        }
        session.requestedTab = null
    }

    if (showOpening) {
        OpeningIntroOverlay { showOpening = false }
        return
    }

    if (!introCompleted) {
        IntroScreen { introCompleted = true }
        return
    }

    if (!session.isSignedIn) {
        WelcomeScreen(session)
        return
    }

    Scaffold(
        containerColor = bgColor,
        bottomBar = {
            AnimatedVisibility(
                visible = !session.isStreaming,
                enter = slideInVertically { it } + fadeIn(),
                exit = slideOutVertically { it } + fadeOut()
            ) {
                NavigationBar(containerColor = Color(0xF014141A)) {
                    val itemColors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Color.White,
                        selectedTextColor = Color.White,
                        unselectedIconColor = Color(0xFF909098),
                        unselectedTextColor = Color(0xFF909098),
                        indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.35f)
                    )
                    NavigationBarItem(
                        selected = tab == Tab.Library,
                        onClick = {
                            tab = Tab.Library
                            tabPrefs.edit().putString("selectedTab", Tab.Library.name).apply()
                        },
                        icon = { Icon(Icons.Default.GridView, contentDescription = null) },
                        label = { Text("Library") },
                        colors = itemColors
                    )
                    NavigationBarItem(
                        selected = tab == Tab.Search,
                        onClick = {
                            tab = Tab.Search
                            tabPrefs.edit().putString("selectedTab", Tab.Search.name).apply()
                        },
                        icon = { Icon(Icons.Default.Search, contentDescription = null) },
                        label = { Text("Search") },
                        colors = itemColors
                    )
                    NavigationBarItem(
                        selected = tab == Tab.Settings,
                        onClick = {
                            tab = Tab.Settings
                            tabPrefs.edit().putString("selectedTab", Tab.Settings.name).apply()
                        },
                        icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                        label = { Text("Settings") },
                        colors = itemColors
                    )
                }
            }
        }
    ) { padding ->
        Box(
            Modifier
                .padding(if (session.isStreaming) PaddingValues(0.dp) else padding)
                .fillMaxSize()
        ) {
            when (tab) {
                Tab.Library -> LibraryScreen(session)
                Tab.Search -> SearchScreen(session)
                Tab.Settings -> SettingsScreen(session)
            }
        }
    }
}
