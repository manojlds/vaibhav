package com.vaibhav.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF8BE9FD),
    secondary = Color(0xFF50FA7B),
    tertiary = Color(0xFFFF79C6),
    background = Color(0xFF1A1A2E),
    surface = Color(0xFF16213E),
    onPrimary = Color.Black,
    onSecondary = Color.Black,
    onTertiary = Color.Black,
    onBackground = Color(0xFFF8F8F2),
    onSurface = Color(0xFFF8F8F2),
    surfaceVariant = Color(0xFF2A2A4A),
    onSurfaceVariant = Color(0xFFBBBBBB),
    outline = Color(0xFF444466),
)

@Composable
fun VaibhavTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        content = content
    )
}
