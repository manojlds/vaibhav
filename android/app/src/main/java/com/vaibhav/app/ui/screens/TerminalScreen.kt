package com.vaibhav.app.ui.screens

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import android.widget.Toast
import androidx.activity.compose.BackHandler
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
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.vaibhav.app.data.VaibhavApi
import kotlinx.coroutines.launch
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
    var ctrlLastTap by remember { mutableLongStateOf(0L) }
    var altLastTap by remember { mutableLongStateOf(0L) }
    var webViewRef by remember { mutableStateOf<TerminalWebView?>(null) }
    val initialSession = config.normalizedSessionName
    var currentSessionPath by remember(config.host, config.port, initialSession) { mutableStateOf(initialSession) }
    var activeUrl by remember(config.host, config.port, initialSession) {
        mutableStateOf(
            if (initialSession.isBlank()) "about:blank"
            else "https://${config.host}:${config.port}/$initialSession"
        )
    }
    var isLoading by remember(config.host, config.port, initialSession) { mutableStateOf(initialSession.isNotBlank()) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var errorUrl by remember { mutableStateOf("") }
    var showSwitcher by remember { mutableStateOf(false) }
    var retryInProgress by remember { mutableStateOf(false) }
    var lastConnectionToastMessage by remember { mutableStateOf("") }
    var lastConnectionToastAt by remember { mutableLongStateOf(0L) }
    var lastBackPressAt by remember { mutableLongStateOf(0L) }
    val appContext = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val lastKnownTabBySession = remember { mutableStateMapOf<String, String>() }
    var restoreRequest by remember { mutableStateOf<Pair<String, String>?>(null) }
    var appInForeground by remember { mutableStateOf(true) }
    var restoreInFlight by remember { mutableStateOf(false) }

    fun rememberActiveTab(sessionName: String, tabName: String?) {
        val normalizedSession = sessionName.trim().trim('/')
        val normalizedTab = tabName?.trim().orEmpty()
        if (normalizedSession.isNotBlank() && normalizedTab.isNotBlank()) {
            lastKnownTabBySession[normalizedSession] = normalizedTab
        }
    }

    fun showConnectionToast(message: String) {
        val now = SystemClock.uptimeMillis()
        val isDuplicate =
            message == lastConnectionToastMessage && (now - lastConnectionToastAt) < 2500L
        if (!isDuplicate) {
            Toast.makeText(appContext, message, Toast.LENGTH_LONG).show()
            lastConnectionToastMessage = message
            lastConnectionToastAt = now
        }
    }

    fun normalizeUrl(url: String): String = url.trim().trimEnd('/')

    DisposableEffect(lifecycleOwner, config.filesBaseUrl, currentSessionPath, activeUrl) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> {
                    appInForeground = false

                    val sessionAtPause = currentSessionPath.trim().trim('/')
                    if (sessionAtPause.isBlank() || activeUrl == "about:blank") return@LifecycleEventObserver

                    lastKnownTabBySession[sessionAtPause]?.let { knownTab ->
                        if (knownTab.isNotBlank()) {
                            restoreRequest = sessionAtPause to knownTab
                        }
                    }

                    scope.launch {
                        val response = VaibhavApi.getActiveTab(config.filesBaseUrl, sessionAtPause)
                        val activeTab = response.activeTab?.trim().orEmpty()
                        if (response.ok && activeTab.isNotBlank()) {
                            rememberActiveTab(sessionAtPause, activeTab)
                            restoreRequest = sessionAtPause to activeTab
                        }
                    }
                }

                Lifecycle.Event.ON_RESUME -> {
                    appInForeground = true
                }

                else -> Unit
            }
        }

        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    LaunchedEffect(appInForeground, restoreRequest, currentSessionPath, activeUrl, config.filesBaseUrl) {
        if (!appInForeground || restoreInFlight) return@LaunchedEffect
        val req = restoreRequest ?: return@LaunchedEffect

        val activeSession = currentSessionPath.trim().trim('/')
        if (activeSession.isBlank() || activeUrl == "about:blank") return@LaunchedEffect

        val reqSession = req.first.trim().trim('/')
        val reqTab = req.second.trim()
        if (reqSession.isBlank() || reqTab.isBlank()) {
            restoreRequest = null
            return@LaunchedEffect
        }
        if (reqSession != activeSession) {
            return@LaunchedEffect
        }

        restoreInFlight = true
        try {
            kotlinx.coroutines.delay(900)

            var response = VaibhavApi.focusTab(config.filesBaseUrl, reqSession, reqTab)
            var attempts = 0
            val maxAttempts = 6
            while (attempts < maxAttempts && response.ok && response.pending) {
                attempts += 1
                kotlinx.coroutines.delay(700)
                response = VaibhavApi.focusTab(config.filesBaseUrl, reqSession, reqTab)
            }

            if (response.ok && response.focused) {
                rememberActiveTab(reqSession, reqTab)
            }
        } finally {
            restoreInFlight = false
            restoreRequest = null
        }
    }

    LaunchedEffect(config.host, config.port, initialSession) {
        if (initialSession.isBlank()) {
            // Do not load an arbitrary session; open switcher first.
            activeUrl = "about:blank"
            isLoading = false
            loadError = null
            errorUrl = ""
            showSwitcher = true
            onSwitcherRequest()
        }
    }

    BackHandler(enabled = true) {
        if (showSwitcher) {
            showSwitcher = false
            return@BackHandler
        }

        val now = SystemClock.uptimeMillis()
        if (now - lastBackPressAt < 1500L) {
            (appContext as? Activity)?.finish()
        } else {
            lastBackPressAt = now
            Toast.makeText(appContext, "Swipe back again to exit", Toast.LENGTH_SHORT).show()
        }
    }

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

    Column(modifier = modifier.fillMaxSize().imePadding()) {
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
                                    webViewRef?.focusTerminalInput()
                                    if (retryInProgress) {
                                        Toast.makeText(appContext, "Reconnected", Toast.LENGTH_SHORT).show()
                                        retryInProgress = false
                                    }

                                    val sessionName = currentSessionPath.trim().trim('/')
                                    if (sessionName.isNotBlank() && activeUrl != "about:blank") {
                                        scope.launch {
                                            val response = VaibhavApi.getActiveTab(config.filesBaseUrl, sessionName)
                                            val activeTab = response.activeTab?.trim().orEmpty()
                                            if (response.ok && activeTab.isNotBlank()) {
                                                rememberActiveTab(sessionName, activeTab)
                                            }
                                        }
                                    }
                                }
                            }

                            override fun onReceivedError(
                                view: WebView?,
                                request: WebResourceRequest?,
                                error: WebResourceError?
                            ) {
                                if (request?.isForMainFrame == true) {
                                    val failingUrl = request.url?.toString() ?: ""
                                    val message = error?.description?.toString() ?: "Connection failed"

                                    if (failingUrl == "about:blank") return
                                    if (message.contains("ERR_ABORTED", ignoreCase = true)) return
                                    if (activeUrl != "about:blank" &&
                                        normalizeUrl(failingUrl) != normalizeUrl(activeUrl)
                                    ) return

                                    loadError = message
                                    errorUrl = failingUrl
                                    isLoading = false
                                    retryInProgress = false
                                    showConnectionToast("Cannot connect: $message")
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
                                    val failingUrl = request.url?.toString() ?: ""
                                    val code = errorResponse?.statusCode ?: 0
                                    if (code >= 400) {
                                        if (failingUrl == "about:blank") return
                                        if (activeUrl != "about:blank" &&
                                            normalizeUrl(failingUrl) != normalizeUrl(activeUrl)
                                        ) return

                                        loadError = "HTTP $code"
                                        errorUrl = failingUrl
                                        isLoading = false
                                        retryInProgress = false
                                        showConnectionToast("Cannot connect: HTTP $code")
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

                        loadUrl(activeUrl)

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
                            retryInProgress = true
                            Toast.makeText(appContext, "Retrying connection...", Toast.LENGTH_SHORT).show()
                            webViewRef?.visibility = View.VISIBLE
                            webViewRef?.loadUrl(activeUrl)
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
            onKeyPress = { keyCode ->
                if (keyCode == KeyEvent.KEYCODE_DEL) {
                    webViewRef?.sendBackspace(false, false, false)
                } else {
                    webViewRef?.dispatchKeyWithModifiers(keyCode)
                }
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
            onKeyboardRequest = {
                webViewRef?.showKeyboard()
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
                val normalizedSession = sessionName.trim().trim('/')
                currentSessionPath = normalizedSession
                val url = "https://${config.host}:${config.port}/$normalizedSession"
                activeUrl = url
                loadError = null
                errorUrl = ""
                isLoading = true
                retryInProgress = false
                restoreRequest = null
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
            function patchStyle() {
                if (document.getElementById('__vaibhav_terminal_style__')) return;
                var style = document.createElement('style');
                style.id = '__vaibhav_terminal_style__';
                style.innerHTML = `$css`;
                document.head.appendChild(style);
            }

            function sendDelByte() {
                try {
                    if (window.term && typeof window.term.input === 'function') {
                        window.term.input(String.fromCharCode(127)); // DEL (^?)
                        return true;
                    }
                } catch (e) {}
                return false;
            }

            function wireTextAreaBackspace(ta) {
                if (!ta || ta.__vaibhavBackspaceWired) return;
                ta.__vaibhavBackspaceWired = true;

                ta.addEventListener('beforeinput', function(ev) {
                    if (!ev) return;
                    if (ev.inputType === 'deleteContentBackward') {
                        ev.preventDefault();
                        ev.stopPropagation();
                        sendDelByte();
                    }
                }, true);

                ta.addEventListener('input', function(ev) {
                    if (!ev) return;
                    if (ev.inputType === 'deleteContentBackward') {
                        ta.value = '';
                        sendDelByte();
                    }
                }, true);
            }

            function fixTextArea() {
                var ta = document.querySelector('.xterm-helper-textarea');
                if (!ta) return null;
                ta.setAttribute('autocorrect', 'off');
                ta.setAttribute('autocapitalize', 'off');
                ta.setAttribute('spellcheck', 'false');
                ta.setAttribute('autocomplete', 'off');
                ta.setAttribute('inputmode', 'text');
                wireTextAreaBackspace(ta);
                return ta;
            }

            function focusTextArea() {
                var ta = fixTextArea();
                if (ta) {
                    ta.focus();
                }
            }

            function installBackspaceBridge() {
                if (window.__vaibhavBackspaceBridgeInstalled) return;
                window.__vaibhavBackspaceBridgeInstalled = true;

                document.addEventListener('keydown', function(ev) {
                    if (!ev || ev.key !== 'Backspace') return;
                    var target = ev.target;
                    var active = document.activeElement;
                    var inTerminal = false;
                    if (target && target.classList && target.classList.contains('xterm-helper-textarea')) {
                        inTerminal = true;
                    } else if (target && target.closest && target.closest('.xterm')) {
                        inTerminal = true;
                    } else if (active && active.classList && active.classList.contains('xterm-helper-textarea')) {
                        inTerminal = true;
                    }
                    if (!inTerminal) return;

                    ev.preventDefault();
                    ev.stopPropagation();
                    sendDelByte();
                }, true);
            }

            if (!window.__vaibhav_terminal_patched__) {
                window.__vaibhav_terminal_patched__ = true;
                patchStyle();
                installBackspaceBridge();

                document.addEventListener('pointerdown', function(ev) {
                    var target = ev && ev.target;
                    if (target && target.closest && target.closest('.xterm')) {
                        setTimeout(focusTextArea, 0);
                    }
                }, true);

                window.addEventListener('focus', function() {
                    setTimeout(focusTextArea, 0);
                });

                setInterval(fixTextArea, 700);
            }

            patchStyle();
            installBackspaceBridge();
            focusTextArea();
        })();
    """.trimIndent()
    view?.evaluateJavascript(js, null)
}
