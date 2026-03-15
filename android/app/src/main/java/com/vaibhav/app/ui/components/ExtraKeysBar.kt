package com.vaibhav.app.ui.components

import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vaibhav.app.model.ModifierState

data class ExtraKeyAction(
    val label: String,
    val keyCode: Int = 0,
    val text: String = "",
    val isModifier: Boolean = false
)

@Composable
fun ExtraKeysBar(
    ctrlState: ModifierState,
    altState: ModifierState,
    onKeyPress: (keyCode: Int) -> Unit,
    onCtrlToggle: () -> Unit,
    onAltToggle: () -> Unit,
    onKeyboardRequest: () -> Unit,
    modifier: Modifier = Modifier
) {
    val barColor = Color(0xFF1E1E2E)
    val keyColor = Color(0xFF2D2D44)
    val activeColor = Color(0xFF8BE9FD)
    val lockedColor = Color(0xFFFF79C6)
    val textColor = Color(0xFFF8F8F2)

    Column(modifier = modifier.background(barColor)) {
        // Main row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 2.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            KeyButton("ESC", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_ESCAPE)
            }

            ModifierButton(
                label = "CTRL",
                state = ctrlState,
                normalColor = keyColor,
                activeColor = activeColor,
                lockedColor = lockedColor,
                textColor = textColor,
                modifier = Modifier.weight(1f),
                onClick = onCtrlToggle
            )

            ModifierButton(
                label = "ALT",
                state = altState,
                normalColor = keyColor,
                activeColor = activeColor,
                lockedColor = lockedColor,
                textColor = textColor,
                modifier = Modifier.weight(1f),
                onClick = onAltToggle
            )

            KeyButton("TAB", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_TAB)
            }

            KeyButton("⌫", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_DEL)
            }

            KeyButton("KBD", keyColor, textColor, Modifier.weight(1f)) {
                onKeyboardRequest()
            }
        }

        // Navigation row (always visible)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 2.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            KeyButton("PgUp", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_PAGE_UP)
            }
            KeyButton("Home", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_MOVE_HOME)
            }
            KeyButton("◀", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_DPAD_LEFT)
            }
            KeyButton("▲", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_DPAD_UP)
            }
            KeyButton("▼", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_DPAD_DOWN)
            }
            KeyButton("▶", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_DPAD_RIGHT)
            }
            KeyButton("End", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_MOVE_END)
            }
            KeyButton("PgDn", keyColor, textColor, Modifier.weight(1f)) {
                onKeyPress(KeyEvent.KEYCODE_PAGE_DOWN)
            }
        }
    }
}

@Composable
private fun KeyButton(
    label: String,
    backgroundColor: Color,
    textColor: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Box(
        modifier = modifier
            .padding(1.dp)
            .height(36.dp)
            .background(backgroundColor, RoundedCornerShape(4.dp))
            .border(0.5.dp, Color(0xFF444466), RoundedCornerShape(4.dp))
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        if (event.changes.any { it.pressed && !it.previousPressed }) {
                            onClick()
                            event.changes.forEach { it.consume() }
                        }
                    }
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            color = textColor,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = FontFamily.Monospace,
            textAlign = TextAlign.Center,
            maxLines = 1
        )
    }
}

@Composable
private fun ModifierButton(
    label: String,
    state: ModifierState,
    normalColor: Color,
    activeColor: Color,
    lockedColor: Color,
    textColor: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val bgColor = when (state) {
        ModifierState.OFF -> normalColor
        ModifierState.ON -> activeColor
        ModifierState.LOCKED -> lockedColor
    }
    val fgColor = when (state) {
        ModifierState.OFF -> textColor
        else -> Color.Black
    }

    Box(
        modifier = modifier
            .padding(1.dp)
            .height(36.dp)
            .background(bgColor, RoundedCornerShape(4.dp))
            .border(0.5.dp, Color(0xFF444466), RoundedCornerShape(4.dp))
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        if (event.changes.any { it.pressed && !it.previousPressed }) {
                            onClick()
                            event.changes.forEach { it.consume() }
                        }
                    }
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = if (state == ModifierState.LOCKED) "◉ $label" else label,
            color = fgColor,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            textAlign = TextAlign.Center,
            maxLines = 1
        )
    }
}
