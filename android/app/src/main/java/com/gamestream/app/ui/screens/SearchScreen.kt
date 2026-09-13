package com.gamestream.app.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.gamestream.app.SessionStore

@Composable
fun SearchScreen(session: SessionStore) {
    var query by remember { mutableStateOf("") }

    fun go() {
        val q = query.trim()
        if (q.isNotEmpty()) session.openSearch(q)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp)
    ) {
        Text(
            "Search",
            style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold),
            color = Color.White
        )
        Text(
            "Find your next game",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFFB0B0B8)
        )
        Spacer(Modifier.height(20.dp))

        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Search games") },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { go() })
        )

        Spacer(Modifier.height(16.dp))

        Button(
            onClick = { go() },
            modifier = Modifier.fillMaxWidth(),
            enabled = query.isNotBlank()
        ) {
            Text("Search Xbox Cloud Gaming")
        }

        if (query.isNotBlank()) {
            Spacer(Modifier.height(12.dp))
            Text(
                "Opens Library and searches for \"${query.trim()}\".",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF808088)
            )
        }
    }
}
