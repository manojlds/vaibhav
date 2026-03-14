package com.vaibhav.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import com.vaibhav.app.data.ConnectionStore
import com.vaibhav.app.model.ConnectionConfig
import com.vaibhav.app.ui.screens.ConnectionScreen
import com.vaibhav.app.ui.screens.TerminalScreen
import com.vaibhav.app.ui.theme.VaibhavTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val store = ConnectionStore(this)

        setContent {
            VaibhavTheme {
                var screen by remember { mutableStateOf<AppScreen>(AppScreen.Loading) }
                var activeConnection by remember { mutableStateOf<ConnectionConfig?>(null) }
                var editingConfig by remember { mutableStateOf<ConnectionConfig?>(null) }

                // Initial navigation
                LaunchedEffect(Unit) {
                    val last = store.loadLast()
                    if (last != null) {
                        activeConnection = last
                        screen = AppScreen.Terminal
                    } else {
                        screen = AppScreen.NewConnection
                    }
                }

                when (screen) {
                    AppScreen.Loading -> {}

                    AppScreen.NewConnection -> {
                        ConnectionScreen(
                            existingConfig = editingConfig,
                            onSave = { config ->
                                store.saveLast(config)
                                activeConnection = config
                                editingConfig = null
                                screen = AppScreen.Terminal
                            },
                            onBack = {
                                editingConfig = null
                                if (activeConnection != null) {
                                    screen = AppScreen.Terminal
                                }
                            }
                        )
                    }

                    AppScreen.Terminal -> {
                        activeConnection?.let { config ->
                            TerminalScreen(
                                config = config,
                                onSwitcherRequest = { /* handled internally now */ },
                                onConnectionSettings = {
                                    editingConfig = config
                                    screen = AppScreen.NewConnection
                                },
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(MaterialTheme.colorScheme.background)
                            )
                        }
                    }
                }
            }
        }
    }
}

private enum class AppScreen {
    Loading, NewConnection, Terminal
}
