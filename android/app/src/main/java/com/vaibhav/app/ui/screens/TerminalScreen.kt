package com.vaibhav.app.ui.screens

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.vaibhav.app.model.ConnectionConfig
import com.vaibhav.app.model.ModifierState
import com.vaibhav.app.ui.ModifierProvider
import com.vaibhav.app.ui.TerminalWebView
import com.vaibhav.app.ui.components.ExtraKeysBar
import com.vaibhav.app.ui.components.VaibhavSwitcher

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun TerminalScreen(
    config: ConnectionConfig,
    onSwitcherRequest: () -> Unit,
    onConnectionSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    var ctrlState by remember { mutableStateOf(ModifierState.OFF) }
    var altState by remember { mutableStateOf(ModifierState.OFF) }
    var showArrows by remember { mutableStateOf(false) }
    var ctrlLastTap by remember { mutableLongStateOf(0L) }
    var altLastTap by remember { mutableLongStateOf(0L) }
    var webViewRef by remember { mutableStateOf<TerminalWebView?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var errorUrl by remember { mutableStateOf("") }
    var showSwitcher by remember { mutableStateOf(false) }
    var currentSessionPath by remember { mutableStateOf(config.zellijSessionName) }

    val modifierProvider = remember {
        object : ModifierProvider {
            override fun getMetaState(): Int {
                var state = 0
                if (ctrlState != ModifierState.OFF) state = state or KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON
                if (altState != ModifierState.OFF) state = state or KeyEvent.META_ALT_ON or KeyEvent.META_ALT_LEFT_ON
                return state
            }

            override fun onModifierUsed() {
                if (ctrlState == ModifierState.ON) ctrlState = ModifierState.OFF
                if (altState == ModifierState.ON) altState = ModifierState.OFF
            }
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Top bar with switcher button
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { showSwitcher = true }) {
                Icon(
                    Icons.Default.SwapHoriz,
                    contentDescription = "Vaibhav Switch",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
            if (isLoading) {
                LinearProgressIndicator(
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 8.dp)
                )
            }
        }

        // WebView
        Box(modifier = Modifier.weight(1f)) {
            AndroidView(
                factory = { context ->
                    TerminalWebView(context).apply {
                        layoutParams = ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                        this.modifierProvider = modifierProvider

                        settings.apply {
                            javaScriptEnabled = true
                            domStorageEnabled = true
                            databaseEnabled = true
                            setSupportZoom(true)
                            builtInZoomControls = true
                            displayZoomControls = false
                            userAgentString = "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Vaibhav/1.0"
                            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                            loadWithOverviewMode = true
                            useWideViewPort = true
                            mediaPlaybackRequiresUserGesture = false
                        }

                        webViewClient = object : WebViewClient() {
                            override fun onReceivedSslError(
                                view: WebView?,
                                handler: SslErrorHandler?,
                                error: SslError?
                            ) {
                                handler?.proceed()
                            }

                            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                                super.onPageStarted(view, url, favicon)
                                if (loadError == null) {
                                    view?.visibility = View.VISIBLE
                                }
                            }

                            override fun onPageFinished(view: WebView?, url: String?) {
                                super.onPageFinished(view, url)
                                if (loadError == null) {
                                    isLoading = false
                                    injectTerminalFixes(view)
                                }
                            }

                            override fun onReceivedError(
                                view: WebView?,
                                request: WebResourceRequest?,
                                error: WebResourceError?
                            ) {
                                if (request?.isForMainFrame == true) {
                                    loadError = error?.description?.toString() ?: "Connection failed"
                                    errorUrl = request.url?.toString() ?: ""
                                    isLoading = false
                                    // Hide WebView to suppress Chrome's default error page
                                    view?.visibility = View.INVISIBLE
                                    // Load blank to clear the error page from back stack
                                    view?.loadUrl("about:blank")
                                }
                            }

                            override fun onReceivedHttpError(
                                view: WebView?,
                                request: WebResourceRequest?,
                                errorResponse: WebResourceResponse?
                            ) {
                                if (request?.isForMainFrame == true) {
                                    val code = errorResponse?.statusCode ?: 0
                                    if (code >= 400) {
                                        loadError = "HTTP $code"
                                        errorUrl = request.url?.toString() ?: ""
                                        isLoading = false
                                        view?.visibility = View.INVISIBLE
                                        view?.loadUrl("about:blank")
                                    }
                                }
                            }
                        }

                        webChromeClient = WebChromeClient()

                        // Set up swipe to switch zellij tabs
                        this.onZellijTabSwipeListener = { direction ->
                            val keyCode = when (direction) {
                                TerminalWebView.SwipeDirection.LEFT -> KeyEvent.KEYCODE_DPAD_LEFT
                                TerminalWebView.SwipeDirection.RIGHT -> KeyEvent.KEYCODE_DPAD_RIGHT
                            }
                            dispatchKeyWithModifiers(
                                keyCode,
                                KeyEvent.META_ALT_ON or KeyEvent.META_ALT_LEFT_ON
                            )
                        }

                        loadUrl(config.zellijWebUrl)

                        webViewRef = this
                    }
                },
                modifier = Modifier.fillMaxSize()
            )

            // Error overlay — replaces the WebView entirely on error
            loadError?.let { error ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.background),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(32.dp)
                    ) {
                        Icon(
                            Icons.Default.WifiOff,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(48.dp)
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            "Cannot Connect",
                            style = MaterialTheme.typography.titleLarge,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            error,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.error,
                            textAlign = TextAlign.Center
                        )
                        if (errorUrl.isNotBlank()) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                errorUrl,
                                fontFamily = FontFamily.Monospace,
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center
                            )
                        }
                        Spacer(modifier = Modifier.height(24.dp))
                        Button(onClick = {
                            loadError = null
                            errorUrl = ""
                            isLoading = true
                            webViewRef?.visibility = View.VISIBLE
                            webViewRef?.loadUrl(config.zellijWebUrl)
                        }) {
                            Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Retry", fontFamily = FontFamily.Monospace)
                        }
                        Spacer(modifier = Modifier.height(12.dp))
                        TextButton(onClick = onConnectionSettings) {
                            Icon(Icons.Default.SwapHoriz, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Connection Settings", fontFamily = FontFamily.Monospace, fontSize = 13.sp)
                        }
                    }
                }
            }
        }

        // Extra keys bar
        ExtraKeysBar(
            ctrlState = ctrlState,
            altState = altState,
            showArrows = showArrows,
            onKeyPress = { keyCode ->
                webViewRef?.dispatchKeyWithModifiers(keyCode)
                if (ctrlState == ModifierState.ON) ctrlState = ModifierState.OFF
                if (altState == ModifierState.ON) altState = ModifierState.OFF
            },
            onTextKey = { text ->
                val ctrl = ctrlState != ModifierState.OFF
                val alt = altState != ModifierState.OFF
                webViewRef?.sendKeyViaJavascript(text, ctrl, alt, false)
                if (ctrlState == ModifierState.ON) ctrlState = ModifierState.OFF
                if (altState == ModifierState.ON) altState = ModifierState.OFF
            },
            onCtrlToggle = {
                val now = SystemClock.uptimeMillis()
                ctrlState = ctrlState.next(ctrlLastTap, now)
                ctrlLastTap = now
            },
            onAltToggle = {
                val now = SystemClock.uptimeMillis()
                altState = altState.next(altLastTap, now)
                altLastTap = now
            },
            onArrowToggle = { showArrows = !showArrows },
            onArrowSwipe = { keyCode ->
                webViewRef?.dispatchKeyWithModifiers(keyCode)
            },
            modifier = Modifier.navigationBarsPadding()
        )
    }

    // Vaibhav session switcher
    if (showSwitcher) {
        VaibhavSwitcher(
            config = config,
            currentSessionPath = currentSessionPath,
            onSessionSelect = { sessionName ->
                showSwitcher = false
                currentSessionPath = sessionName
                val url = "https://${config.host}:${config.port}/$sessionName"
                loadError = null
                errorUrl = ""
                isLoading = true
                webViewRef?.visibility = View.VISIBLE
                webViewRef?.loadUrl(url)
            },
            onConnectionSettings = {
                showSwitcher = false
                onConnectionSettings()
            },
            onDismiss = { showSwitcher = false }
        )
    }
}

private fun injectTerminalFixes(view: WebView?) {
    val css = """
        .xterm .xterm-screen canvas { font-family: monospace !important; }
        .xterm { font-family: monospace !important; }
    """.trimIndent()

    val js = """
        (function() {
            var style = document.createElement('style');
            style.innerHTML = `$css`;
            document.head.appendChild(style);

            function fixTextArea() {
                var ta = document.querySelector('.xterm-helper-textarea');
                if (ta) {
                    ta.setAttribute('autocorrect', 'off');
                    ta.setAttribute('autocapitalize', 'off');
                    ta.setAttribute('spellcheck', 'false');
                    ta.setAttribute('autocomplete', 'off');
                }
            }
            setInterval(fixTextArea, 1000);
            fixTextArea();
        })();
    """.trimIndent()
    view?.evaluateJavascript(js, null)
}
