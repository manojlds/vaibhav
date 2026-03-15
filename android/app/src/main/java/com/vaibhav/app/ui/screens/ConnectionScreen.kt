package com.vaibhav.app.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.vaibhav.app.model.ConnectionConfig

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectionScreen(
    existingConfig: ConnectionConfig? = null,
    onSave: (ConnectionConfig) -> Unit,
    onBack: () -> Unit
) {
    var name by remember { mutableStateOf(existingConfig?.name ?: "") }
    var host by remember { mutableStateOf(existingConfig?.host ?: "") }
    var port by remember { mutableStateOf((existingConfig?.port ?: 8443).toString()) }
    var filesPort by remember { mutableStateOf((existingConfig?.filesPort ?: 9443).toString()) }
    var sessionName by remember { mutableStateOf(existingConfig?.zellijSessionName ?: "") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (existingConfig != null) "Edit Connection" else "New Connection",
                        fontFamily = FontFamily.Monospace
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name") },
                placeholder = { Text("e.g. My Desktop") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = host,
                onValueChange = { host = it },
                label = { Text("Host") },
                placeholder = { Text("e.g. mypc or 100.64.1.5") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = port,
                    onValueChange = { port = it },
                    label = { Text("Zellij Port") },
                    placeholder = { Text("8443") },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                OutlinedTextField(
                    value = filesPort,
                    onValueChange = { filesPort = it },
                    label = { Text("Files Port") },
                    placeholder = { Text("9443") },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
            }

            OutlinedTextField(
                value = sessionName,
                onValueChange = { sessionName = it },
                label = { Text("Zellij Session Name (optional)") },
                placeholder = { Text("e.g. heimdall") },
                supportingText = { Text("Leave blank to open switcher first and choose a project/session.") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Spacer(modifier = Modifier.weight(1f))

            Button(
                onClick = {
                    onSave(
                        ConnectionConfig(
                            name = name.ifBlank { host },
                            host = host,
                            port = port.toIntOrNull() ?: 8443,
                            filesPort = filesPort.toIntOrNull() ?: 9443,
                            zellijSessionName = sessionName
                        )
                    )
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = host.isNotBlank()
            ) {
                Text("Connect", fontFamily = FontFamily.Monospace)
            }
        }
    }
}
