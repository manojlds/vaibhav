package com.vaibhav.app.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.vaibhav.app.data.VaibhavApi
import com.vaibhav.app.data.VaibhavProject
import com.vaibhav.app.data.VaibhavStatus
import com.vaibhav.app.model.ConnectionConfig
import kotlinx.coroutines.launch

@Composable
fun VaibhavSwitcher(
    config: ConnectionConfig,
    currentSessionPath: String,
    onSessionSelect: (String) -> Unit,
    onConnectionSettings: () -> Unit,
    onDismiss: () -> Unit
) {
    var status by remember { mutableStateOf<VaibhavStatus?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var fetchError by remember { mutableStateOf<String?>(null) }
    var filter by remember { mutableStateOf("") }
    var killConfirm by remember { mutableStateOf<String?>(null) }
    var toolPickerProject by remember { mutableStateOf<String?>(null) }
    var isActioning by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val focusRequester = remember { FocusRequester() }

    fun refresh() {
        isLoading = true
        fetchError = null
        scope.launch {
            val result = VaibhavApi.fetchStatus(config.filesBaseUrl)
            status = result
            isLoading = false
            if (result.projects.isEmpty() && result.sessions.isEmpty()) {
                fetchError = "No data from ${config.filesBaseUrl}/api/status"
            }
        }
    }

    LaunchedEffect(config.filesBaseUrl) { refresh() }
    LaunchedEffect(Unit) {
        try { focusRequester.requestFocus() } catch (_: Exception) {}
    }

    // Build display items
    val items = remember(status, filter) {
        val s = status ?: return@remember emptyList()
        val allItems = mutableListOf<SwitcherItem>()
        s.projects.filter { it.active }.forEach { proj ->
            allItems.add(SwitcherItem(proj.name, isActive = true, isProject = true))
        }
        val projectNames = s.projects.map { it.name }.toSet()
        s.sessions.filter { it !in projectNames }.forEach { sess ->
            allItems.add(SwitcherItem(sess, isActive = true, isProject = false))
        }
        s.projects.filter { !it.active }.forEach { proj ->
            allItems.add(SwitcherItem(proj.name, isActive = false, isProject = true))
        }
        if (filter.isBlank()) allItems
        else allItems.filter { fuzzyMatch(it.name, filter) }
            .sortedByDescending { fuzzyScore(it.name, filter) }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(0.92f).fillMaxHeight(0.8f),
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth()
                        .padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("⚡ Vaibhav Switch",
                        style = MaterialTheme.typography.titleMedium,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.weight(1f))
                    IconButton(onClick = { refresh() }) {
                        Icon(Icons.Default.Refresh, "Refresh",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
                    }
                    IconButton(onClick = onConnectionSettings) {
                        Icon(Icons.Default.Settings, "Settings",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, "Close", modifier = Modifier.size(20.dp))
                    }
                }

                // Search
                OutlinedTextField(
                    value = filter, onValueChange = { filter = it },
                    placeholder = { Text("Filter...", fontFamily = FontFamily.Monospace, fontSize = 13.sp) },
                    leadingIcon = { Icon(Icons.Default.Search, null, modifier = Modifier.size(18.dp)) },
                    modifier = Modifier.fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .focusRequester(focusRequester),
                    singleLine = true,
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace, fontSize = 14.sp),
                    shape = RoundedCornerShape(8.dp)
                )

                Spacer(modifier = Modifier.height(4.dp))

                when {
                    isLoading -> {
                        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(modifier = Modifier.size(32.dp))
                        }
                    }
                    items.isEmpty() && filter.isNotBlank() -> {
                        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                            Text("No matches for \"$filter\"",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontFamily = FontFamily.Monospace, fontSize = 13.sp)
                        }
                    }
                    items.isEmpty() -> {
                        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally,
                                modifier = Modifier.padding(16.dp)) {
                                Text("Could not fetch projects",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    fontFamily = FontFamily.Monospace, fontSize = 13.sp)
                                if (fetchError != null) {
                                    Spacer(Modifier.height(4.dp))
                                    Text(fetchError!!, color = MaterialTheme.colorScheme.error,
                                        fontFamily = FontFamily.Monospace, fontSize = 11.sp)
                                }
                                Spacer(Modifier.height(8.dp))
                                TextButton(onClick = { refresh() }) {
                                    Text("Retry", fontFamily = FontFamily.Monospace)
                                }
                            }
                        }
                    }
                    else -> {
                        LazyColumn(
                            modifier = Modifier.weight(1f),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            items(items, key = { it.name }) { item ->
                                val isCurrent = item.name == currentSessionPath
                                SwitcherItemRow(
                                    item = item, isCurrent = isCurrent,
                                    onClick = {
                                        if (item.isActive) {
                                            onSessionSelect(item.name)
                                        } else {
                                            toolPickerProject = item.name
                                        }
                                    },
                                    onKillRequest = if (item.isActive) {
                                        { killConfirm = item.name }
                                    } else null
                                )
                            }
                        }
                    }
                }

                // Loading overlay for actions
                if (isActioning) {
                    Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text("Starting...", fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }

    // Kill confirmation dialog
    killConfirm?.let { sessionName ->
        AlertDialog(
            onDismissRequest = { killConfirm = null },
            title = { Text("Kill Session", fontFamily = FontFamily.Monospace) },
            text = { Text("Kill session \"$sessionName\"?", fontFamily = FontFamily.Monospace, fontSize = 14.sp) },
            confirmButton = {
                TextButton(
                    onClick = {
                        val name = sessionName
                        killConfirm = null
                        scope.launch {
                            VaibhavApi.killSession(config.filesBaseUrl, name)
                            refresh()
                        }
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) { Text("Kill", fontFamily = FontFamily.Monospace) }
            },
            dismissButton = {
                TextButton(onClick = { killConfirm = null }) {
                    Text("Cancel", fontFamily = FontFamily.Monospace)
                }
            }
        )
    }

    // Tool picker dialog
    toolPickerProject?.let { projectName ->
        val tools = listOf(
            "amp" to "Amp",
            "claude" to "Claude Code",
            "pi" to "pi",
            "opencode" to "OpenCode",
            "codex" to "Codex",
            "" to "Shell only"
        )
        AlertDialog(
            onDismissRequest = { toolPickerProject = null },
            title = {
                Text(projectName, fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.primary)
            },
            text = {
                Column {
                    tools.forEach { (toolId, toolLabel) ->
                        TextButton(
                            onClick = {
                                val proj = projectName
                                val tool = toolId
                                toolPickerProject = null
                                // Navigate first — zellij web creates the session via URL
                                onSessionSelect(proj)
                                // Then add tool tab via API (if a tool was selected)
                                if (tool.isNotBlank()) {
                                    scope.launch {
                                        // Give zellij web a moment to create the session
                                        kotlinx.coroutines.delay(1500)
                                        VaibhavApi.openProject(config.filesBaseUrl, proj, tool)
                                    }
                                }
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Icon(Icons.Default.Terminal, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(toolLabel, fontFamily = FontFamily.Monospace,
                                fontSize = 14.sp, modifier = Modifier.weight(1f))
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { toolPickerProject = null }) {
                    Text("Cancel", fontFamily = FontFamily.Monospace)
                }
            }
        )
    }
}

private data class SwitcherItem(
    val name: String,
    val isActive: Boolean,
    val isProject: Boolean
)

@Composable
private fun SwitcherItemRow(
    item: SwitcherItem,
    isCurrent: Boolean,
    onClick: () -> Unit,
    onKillRequest: (() -> Unit)?
) {
    val bgColor = when {
        isCurrent -> MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
        item.isActive -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.08f)
        else -> Color.Transparent
    }

    Row(
        modifier = Modifier.fillMaxWidth()
            .padding(vertical = 1.dp)
            .background(bgColor, RoundedCornerShape(6.dp))
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (item.isActive) {
            Icon(Icons.Default.Terminal, null,
                tint = MaterialTheme.colorScheme.secondary, modifier = Modifier.size(16.dp))
        } else {
            Icon(Icons.Default.PlayArrow, null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier.size(16.dp))
        }

        Spacer(Modifier.width(10.dp))

        Text(
            text = item.name, fontFamily = FontFamily.Monospace,
            fontWeight = if (isCurrent || item.isActive) FontWeight.Bold else FontWeight.Normal,
            color = when {
                isCurrent -> MaterialTheme.colorScheme.primary
                item.isActive -> MaterialTheme.colorScheme.onSurface
                else -> MaterialTheme.colorScheme.onSurfaceVariant
            },
            fontSize = 14.sp, modifier = Modifier.weight(1f)
        )

        if (item.isActive) {
            if (isCurrent) {
                Text("● current", fontFamily = FontFamily.Monospace, fontSize = 10.sp,
                    color = MaterialTheme.colorScheme.primary)
            }
            if (onKillRequest != null) {
                Spacer(Modifier.width(4.dp))
                IconButton(onClick = onKillRequest, modifier = Modifier.size(28.dp)) {
                    Icon(Icons.Default.Delete, "Kill",
                        tint = MaterialTheme.colorScheme.error.copy(alpha = 0.6f),
                        modifier = Modifier.size(14.dp))
                }
            }
        }
    }
}

private fun fuzzyMatch(target: String, query: String): Boolean {
    val t = target.lowercase()
    val q = query.lowercase()
    var ti = 0
    for (qc in q) {
        val found = t.indexOf(qc, ti)
        if (found < 0) return false
        ti = found + 1
    }
    return true
}

private fun fuzzyScore(target: String, query: String): Int {
    val t = target.lowercase()
    val q = query.lowercase()
    var score = 0; var ti = 0; var prevMatch = -2
    for (qc in q) {
        val found = t.indexOf(qc, ti)
        if (found < 0) return 0
        score += 10
        if (found == prevMatch + 1) score += 5
        if (found == 0) score += 3
        prevMatch = found
        ti = found + 1
    }
    score -= t.length
    return score
}
