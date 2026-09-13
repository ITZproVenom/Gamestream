package com.gamestream.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
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
import androidx.lifecycle.viewmodel.compose.viewModel
import com.gamestream.app.BetterXCloudInjector
import com.gamestream.app.SessionStore
import com.gamestream.app.ui.screens.LibraryScreen
import com.gamestream.app.ui.screens.SearchScreen
import com.gamestream.app.ui.screens.SettingsScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class Tab(val label: String) {
    Library("Library"), Search("Search"), Settings("Settings")
}

@Composable
fun GameStreamApp(session: SessionStore = viewModel()) {
    var tab by remember { mutableStateOf(Tab.Library) }
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) {
            BetterXCloudInjector.ensureFetched(context.applicationContext)
        }
    }

    LaunchedEffect(session.requestedTab) {
        when (session.requestedTab) {
            "library" -> tab = Tab.Library
            "search" -> tab = Tab.Search
            "settings" -> tab = Tab.Settings
        }
        session.requestedTab = null
    }

    Scaffold(
        containerColor = Color(0xFF0A0A12),
        bottomBar = {
            AnimatedVisibility(visible = !session.isStreaming) {
                NavigationBar(containerColor = Color(0xEE14141A)) {
                    NavigationBarItem(
                        selected = tab == Tab.Library,
                        onClick = { tab = Tab.Library },
                        icon = { Icon(Icons.Default.GridView, contentDescription = null) },
                        label = { Text("Library") }
                    )
                    NavigationBarItem(
                        selected = tab == Tab.Search,
                        onClick = { tab = Tab.Search },
                        icon = { Icon(Icons.Default.Search, contentDescription = null) },
                        label = { Text("Search") }
                    )
                    NavigationBarItem(
                        selected = tab == Tab.Settings,
                        onClick = { tab = Tab.Settings },
                        icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                        label = { Text("Settings") }
                    )
                }
            }
        }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (tab) {
                Tab.Library -> LibraryScreen(session)
                Tab.Search -> SearchScreen(session)
                Tab.Settings -> SettingsScreen(session)
            }
        }
    }
}
