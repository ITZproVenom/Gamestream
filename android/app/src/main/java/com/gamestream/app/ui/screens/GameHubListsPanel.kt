package com.gamestream.app.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.gamestream.app.CollectionStore
import com.gamestream.app.SessionStore

@Composable
fun GameHubListsButton(session: SessionStore) {
    val context = LocalContext.current
    val store = remember { CollectionStore(context) }
    var open by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var collections by remember { mutableStateOf(store.collections()) }

    OutlinedButton(onClick = { collections = store.collections(); open = true }) {
        Text("Lists")
    }

    if (open) {
        AlertDialog(
            onDismissRequest = { open = false },
            title = { Text("Your lists") },
            text = {
                Column {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("New list name") },
                        singleLine = true
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(onClick = {
                        store.create(name)
                        name = ""
                        collections = store.collections()
                    }) { Text("Create list") }
                    Spacer(Modifier.height(12.dp))
                    if (collections.isEmpty()) {
                        Text("Create a list, then add games from a title page.")
                    } else {
                        collections.forEach { list ->
                            Text("${list.name} · ${list.gameIds.size}")
                            store.games(list).forEach { game ->
                                TextButton(onClick = { session.playGame(game); open = false }) {
                                    Text("Play ${game.title}", maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                            }
                            TextButton(onClick = {
                                store.delete(list.id)
                                collections = store.collections()
                            }) { Text("Delete ${list.name}") }
                            Spacer(Modifier.height(8.dp))
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { open = false }) { Text("Done") } }
        )
    }
}
