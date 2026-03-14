package com.vaibhav.app.ui.components

import android.view.KeyEvent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
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
import kotlin.math.abs

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
    showArrows: Boolean,
    onKeyPress: (keyCode: Int) -> Unit,
    onTextKey: (text: String) -> Unit,
    onCtrlToggle: () -> Unit,
    onAltToggle: () -> Unit,
    onArrowToggle: () -> Unit,
    onArrowSwipe: (keyCode: Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val barColor = Color(0xFF1E1E2E)
    val keyColor = Color(0xFF2D2D44)
    val activeColor = Color(0xFF8BE9FD)
    val lockedColor = Color(0xFFFF79C6)
    val textColor = Color(0xFFF8F8F2)

    Column(modifier = modifier.background(barColor)) {
        // Arrow keys row (toggle visibility)
        AnimatedVisibility(visible = showArrows) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 2.dp, vertical = 2.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                KeyButton("PgUp", keyColor, textColor, Modifier.weight(1f)) {
                    onKeyPress(KeyEvent.KEYCODE_PAGE_UP)
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
                KeyButton("PgDn", keyColor, textColor, Modifier.weight(1f)) {
                    onKeyPress(KeyEvent.KEYCODE_PAGE_DOWN)
                }
            }
        }

        // Main extra keys row
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

            // Arrow keys toggle / swipe button
            ArrowButton(
                showArrows = showArrows,
                keyColor = keyColor,
                activeColor = activeColor,
                textColor = textColor,
                modifier = Modifier.weight(1f),
                onToggle = onArrowToggle,
                onSwipe = onArrowSwipe
            )
        }

        // Symbols row (Termux-style)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 2.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            val symbols = listOf("-", "/", "|", "~", "{", "}", "[", "]", "_", ":")
            symbols.forEach { sym ->
                KeyButton(sym, keyColor, textColor, Modifier.weight(1f)) {
                    onTextKey(sym)
                }
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

@Composable
private fun ArrowButton(
    showArrows: Boolean,
    keyColor: Color,
    activeColor: Color,
    textColor: Color,
    modifier: Modifier = Modifier,
    onToggle: () -> Unit,
    onSwipe: (keyCode: Int) -> Unit
) {
    val bgColor = if (showArrows) activeColor else keyColor
    val fgColor = if (showArrows) Color.Black else textColor
    val dragThreshold = 60f

    Box(
        modifier = modifier
            .padding(1.dp)
            .height(36.dp)
            .background(bgColor, RoundedCornerShape(4.dp))
            .border(0.5.dp, Color(0xFF444466), RoundedCornerShape(4.dp))
            .pointerInput(Unit) {
                var offsetX = 0f
                var offsetY = 0f
                var isDrag = false

                detectDragGestures(
                    onDragStart = {
                        offsetX = 0f
                        offsetY = 0f
                        isDrag = false
                    },
                    onDrag = { _, dragAmount ->
                        offsetX += dragAmount.x
                        offsetY += dragAmount.y
                        if (abs(offsetX) > dragThreshold || abs(offsetY) > dragThreshold) {
                            isDrag = true
                        }
                    },
                    onDragEnd = {
                        if (isDrag) {
                            val keyCode = when {
                                abs(offsetY) > abs(offsetX) && offsetY > dragThreshold -> KeyEvent.KEYCODE_DPAD_DOWN
                                abs(offsetY) > abs(offsetX) && offsetY < -dragThreshold -> KeyEvent.KEYCODE_DPAD_UP
                                abs(offsetX) > abs(offsetY) && offsetX > dragThreshold -> KeyEvent.KEYCODE_DPAD_RIGHT
                                abs(offsetX) > abs(offsetY) && offsetX < -dragThreshold -> KeyEvent.KEYCODE_DPAD_LEFT
                                else -> null
                            }
                            keyCode?.let { onSwipe(it) }
                        } else {
                            onToggle()
                        }
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = "⇄",
            color = fgColor,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
    }
}
