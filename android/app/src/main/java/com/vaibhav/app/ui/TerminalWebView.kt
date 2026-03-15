package com.vaibhav.app.ui

import android.annotation.SuppressLint
import android.content.Context
import android.os.SystemClock
import android.util.AttributeSet
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.webkit.WebView

interface ModifierProvider {
    fun getMetaState(): Int
    fun onModifierUsed()
}

@SuppressLint("SetJavaScriptEnabled")
class TerminalWebView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : WebView(context, attrs, defStyleAttr) {

    var modifierProvider: ModifierProvider? = null
    var onZellijTabSwipeListener: ((SwipeDirection) -> Unit)? = null

    enum class SwipeDirection { LEFT, RIGHT }

    private var swipeStartX = 0f
    private var swipeStartY = 0f
    private val minSwipeDistance = 150f
    private val edgeSwipeMargin = 50f

    init {
        isFocusable = true
        isFocusableInTouchMode = true
    }

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN || event.actionMasked == MotionEvent.ACTION_UP) {
            post { focusTerminalInput() }
        }
        return super.onTouchEvent(event)
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        val baseConnection = super.onCreateInputConnection(outAttrs)
        outAttrs.imeOptions = outAttrs.imeOptions or
                EditorInfo.IME_FLAG_NO_EXTRACT_UI or
                EditorInfo.IME_FLAG_NO_FULLSCREEN
        outAttrs.inputType = EditorInfo.TYPE_CLASS_TEXT or
                EditorInfo.TYPE_TEXT_FLAG_NO_SUGGESTIONS or
                EditorInfo.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD

        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                focusTerminalInput()

                val provider = modifierProvider
                if (provider != null && provider.getMetaState() != 0 && text?.length == 1) {
                    val char = text[0]
                    val keyCode = getKeyCodeForChar(char)
                    if (keyCode != 0) {
                        val metaState = provider.getMetaState()
                        dispatchTerminalKey(keyCode, metaState)
                        provider.onModifierUsed()
                        return true
                    }
                }

                if (text != null && text.any { it == '\n' || it == '\r' || it == '\b' || it.code == 127 }) {
                    text.forEach { ch ->
                        when {
                            ch == '\n' || ch == '\r' -> {
                                val meta = provider?.getMetaState() ?: 0
                                dispatchTerminalKey(KeyEvent.KEYCODE_ENTER, meta)
                            }
                            ch == '\b' || ch.code == 127 -> {
                                val meta = provider?.getMetaState() ?: 0
                                dispatchTerminalKey(KeyEvent.KEYCODE_DEL, meta)
                            }
                            else -> {
                                val handled = baseConnection?.commitText(ch.toString(), 1)
                                    ?: super.commitText(ch.toString(), 1)
                                if (!handled) {
                                    return false
                                }
                            }
                        }
                    }
                    return true
                }

                return baseConnection?.commitText(text, newCursorPosition)
                    ?: super.commitText(text, newCursorPosition)
            }

            override fun sendKeyEvent(event: KeyEvent): Boolean {
                val provider = modifierProvider
                if (provider != null && provider.getMetaState() != 0) {
                    val modifiedEvent = KeyEvent(
                        event.downTime, event.eventTime, event.action,
                        event.keyCode, event.repeatCount,
                        event.metaState or provider.getMetaState()
                    )
                    if (event.action == KeyEvent.ACTION_UP) {
                        provider.onModifierUsed()
                    }
                    return super.sendKeyEvent(modifiedEvent)
                }
                return baseConnection?.sendKeyEvent(event) ?: super.sendKeyEvent(event)
            }

            override fun performEditorAction(actionCode: Int): Boolean {
                val meta = modifierProvider?.getMetaState() ?: 0
                dispatchTerminalKey(KeyEvent.KEYCODE_ENTER, meta)
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                // Convert backspace to key event for xterm.js compatibility
                if (beforeLength > 0 && afterLength == 0) {
                    val meta = modifierProvider?.getMetaState() ?: 0
                    repeat(beforeLength.coerceAtMost(8)) {
                        dispatchTerminalKey(KeyEvent.KEYCODE_DEL, meta)
                    }
                    return true
                }
                return baseConnection?.deleteSurroundingText(beforeLength, afterLength)
                    ?: super.deleteSurroundingText(beforeLength, afterLength)
            }

            override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int): Boolean {
                if (beforeLength > 0 && afterLength == 0) {
                    val meta = modifierProvider?.getMetaState() ?: 0
                    repeat(beforeLength.coerceAtMost(8)) {
                        dispatchTerminalKey(KeyEvent.KEYCODE_DEL, meta)
                    }
                    return true
                }
                return super.deleteSurroundingTextInCodePoints(beforeLength, afterLength)
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val provider = modifierProvider
        if (provider != null && provider.getMetaState() != 0 && event.metaState == 0) {
            val modifiedEvent = KeyEvent(
                event.downTime, event.eventTime, event.action,
                event.keyCode, event.repeatCount,
                event.metaState or provider.getMetaState()
            )
            if (event.action == KeyEvent.ACTION_UP) {
                provider.onModifierUsed()
            }
            return super.dispatchKeyEvent(modifiedEvent)
        }
        return super.dispatchKeyEvent(event)
    }

    fun dispatchKeyWithModifiers(keyCode: Int, modifiers: Int = 0) {
        focusTerminalInput()
        val meta = modifiers or (modifierProvider?.getMetaState() ?: 0)
        dispatchTerminalKey(keyCode, meta)
    }

    private fun dispatchTerminalKey(keyCode: Int, meta: Int = 0) {
        val now = SystemClock.uptimeMillis()
        dispatchKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0, meta))
        dispatchKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0, meta))
    }

    fun sendKeyViaJavascript(key: String, ctrlActive: Boolean, altActive: Boolean, metaActive: Boolean) {
        focusTerminalInput()
        val js = """
            (function() {
                let target = document.querySelector('.xterm-helper-textarea') || document.activeElement || document.body;
                const options = {
                    key: '$key',
                    ctrlKey: $ctrlActive,
                    altKey: $altActive,
                    metaKey: $metaActive,
                    bubbles: true
                };
                target.dispatchEvent(new KeyboardEvent('keydown', options));
                target.dispatchEvent(new KeyboardEvent('keyup', options));
            })();
        """.trimIndent()
        evaluateJavascript(js, null)
    }

    fun showKeyboard() {
        requestFocus()
        requestFocusFromTouch()
        post {
            focusTerminalInput()
            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
            postDelayed({ imm?.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT) }, 120)
            postDelayed({ imm?.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT) }, 240)
        }
    }

    fun focusTerminalInput() {
        val focusJs = """
            (function() {
                const textarea = document.querySelector('.xterm-helper-textarea');
                if (textarea) {
                    textarea.setAttribute('autocorrect', 'off');
                    textarea.setAttribute('autocapitalize', 'off');
                    textarea.setAttribute('spellcheck', 'false');
                    textarea.setAttribute('autocomplete', 'off');
                    textarea.focus();
                    return;
                }
                if (document && document.body) {
                    document.body.focus();
                }
            })();
        """.trimIndent()
        evaluateJavascript(focusJs, null)
    }

    private fun getKeyCodeForChar(char: Char): Int {
        if (char == '\b' || char.code == 127) return KeyEvent.KEYCODE_DEL
        if (char == '\n' || char == '\r') return KeyEvent.KEYCODE_ENTER

        return when (char.lowercaseChar()) {
            'a' -> KeyEvent.KEYCODE_A; 'b' -> KeyEvent.KEYCODE_B
            'c' -> KeyEvent.KEYCODE_C; 'd' -> KeyEvent.KEYCODE_D
            'e' -> KeyEvent.KEYCODE_E; 'f' -> KeyEvent.KEYCODE_F
            'g' -> KeyEvent.KEYCODE_G; 'h' -> KeyEvent.KEYCODE_H
            'i' -> KeyEvent.KEYCODE_I; 'j' -> KeyEvent.KEYCODE_J
            'k' -> KeyEvent.KEYCODE_K; 'l' -> KeyEvent.KEYCODE_L
            'm' -> KeyEvent.KEYCODE_M; 'n' -> KeyEvent.KEYCODE_N
            'o' -> KeyEvent.KEYCODE_O; 'p' -> KeyEvent.KEYCODE_P
            'q' -> KeyEvent.KEYCODE_Q; 'r' -> KeyEvent.KEYCODE_R
            's' -> KeyEvent.KEYCODE_S; 't' -> KeyEvent.KEYCODE_T
            'u' -> KeyEvent.KEYCODE_U; 'v' -> KeyEvent.KEYCODE_V
            'w' -> KeyEvent.KEYCODE_W; 'x' -> KeyEvent.KEYCODE_X
            'y' -> KeyEvent.KEYCODE_Y; 'z' -> KeyEvent.KEYCODE_Z
            '0' -> KeyEvent.KEYCODE_0; '1' -> KeyEvent.KEYCODE_1
            '2' -> KeyEvent.KEYCODE_2; '3' -> KeyEvent.KEYCODE_3
            '4' -> KeyEvent.KEYCODE_4; '5' -> KeyEvent.KEYCODE_5
            '6' -> KeyEvent.KEYCODE_6; '7' -> KeyEvent.KEYCODE_7
            '8' -> KeyEvent.KEYCODE_8; '9' -> KeyEvent.KEYCODE_9
            ' ' -> KeyEvent.KEYCODE_SPACE
            '/' -> KeyEvent.KEYCODE_SLASH
            '-' -> KeyEvent.KEYCODE_MINUS
            '=' -> KeyEvent.KEYCODE_EQUALS
            '[' -> KeyEvent.KEYCODE_LEFT_BRACKET
            ']' -> KeyEvent.KEYCODE_RIGHT_BRACKET
            '\\' -> KeyEvent.KEYCODE_BACKSLASH
            ';' -> KeyEvent.KEYCODE_SEMICOLON
            '\'' -> KeyEvent.KEYCODE_APOSTROPHE
            ',' -> KeyEvent.KEYCODE_COMMA
            '.' -> KeyEvent.KEYCODE_PERIOD
            '`' -> KeyEvent.KEYCODE_GRAVE
            else -> 0
        }
    }
}
