import SwiftUI
import WebKit

/// The player is a real, long-lived browser session dedicated to one game.
///
/// Pressing Play loads the game's launch URL directly. The shared cookie store
/// holds the xbox.com session established by SignInWebView (verified via the
/// strict xbox-session cookie check). Once the game page loads,
/// streamIsolationJS auto-clicks the Play / Play with ads / Resume button so
/// the actual stream starts instead of parking on the game info page.
/// No navigation is ever cancelled — the player behaves like a browser.
struct StreamPlayerView: View {
    @EnvironmentObject var session: SessionStore
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showChrome = false
    @State private var chromeHideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            XboxCloudWebView(url: $session.webURL)
                .ignoresSafeArea(edges: .all)

            if isLoading {
                PlayLoadingView(title: session.currentGame?.title ?? "")
                    .transition(.opacity)
                    .zIndex(2)
            }

            // Tap top safe area to reveal Exit / Hub; auto-hides so it never
            // stays stuck over the stream or Better xCloud controls.
            streamChrome
                .padding(.top, 8)
                .zIndex(3)
        }
        .edgesIgnoringSafeArea(.all)
        .onReceive(NotificationCenter.default.publisher(for: .webViewLoadingChanged)) { note in
            if let loading = note.object as? Bool {
                if isLoading && !loading {
                    SoundManager.playReady()
                }
                withAnimation(.easeOut(duration: 0.35)) {
                    isLoading = loading
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerStreamPageReached)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isLoading = false
            }
            // Hide chrome once the stream page is live so it is never permanent.
            scheduleChromeHide(after: 2.5)
        }
        .onReceive(NotificationCenter.default.publisher(for: .webViewDidFail)) { note in
            errorMessage = note.object as? String
            isLoading = false
        }
        .onDisappear {
            chromeHideTask?.cancel()
            ControllerRumble.shared.teardown()
        }
    }

    private var streamChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showChrome {
                HStack(spacing: 8) {
                    Button {
                        chromeHideTask?.cancel()
                        session.exitStreamToHub()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Exit")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Exit stream")

                    Button {
                        chromeHideTask?.cancel()
                        session.returnToHub()
                    } label: {
                        Text("Hub")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Open GameHub")

                    if session.nextQueuedGame != nil {
                        Button {
                            chromeHideTask?.cancel()
                            session.playNextFromStream()
                        } label: {
                            Text("Play next")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Play next queued game")
                    }

                    Spacer(minLength: 0)
                }
                if let title = session.currentGame?.title, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 4)
                }
            } else if !isLoading {
                Button {
                    revealChrome()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.glass)
                .opacity(0.55)
                .accessibilityLabel("Show stream controls")
            }
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showChrome)
    }

    private func revealChrome() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showChrome = true
        }
        scheduleChromeHide(after: 4.0)
    }

    private func scheduleChromeHide(after seconds: Double) {
        chromeHideTask?.cancel()
        chromeHideTask = Task { @MainActor in
            let ns = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                showChrome = false
            }
        }
    }
}

struct XboxCloudWebView: UIViewRepresentable {
    @Binding var url: URL
    @EnvironmentObject var session: SessionStore

    /// xCloud only calls playEffect when vibrationActuator exists.
    /// WKWebView often has no actuator — polyfill one that posts to native GCDeviceHaptics.
    static let rumbleBridgeJS = """
    (function() {
        function postRumble(weak, strong, duration) {
            try {
                var w = Number(weak) || 0;
                var s = Number(strong) || 0;
                var d = Number(duration) || 0;
                if (w < 0) w = 0; if (w > 1) w = 1;
                if (s < 0) s = 0; if (s > 1) s = 1;
                if (d < 0) d = 0; if (d > 2500) d = 2500;
                if (w < 0.01 && s < 0.01) return;
                window.webkit.messageHandlers.gamestreamBridge.postMessage({
                    type: 'rumble',
                    weak: w,
                    strong: s,
                    duration: d || 80
                });
            } catch (e) {}
        }
        window.__gsNativeRumble = postRumble;

        function makePolyActuator() {
            return {
                __gsPoly: true,
                __gsWrapped: true,
                playEffect: function(type, params) {
                    try {
                        params = params || {};
                        var weak = params.weakMagnitude != null ? params.weakMagnitude : (params.magnitude || 0);
                        var strong = params.strongMagnitude != null ? params.strongMagnitude : (params.magnitude || 0);
                        var start = params.startDelay || 0;
                        var duration = params.duration || 100;
                        setTimeout(function() { postRumble(weak, strong, duration); }, start);
                    } catch (e) {}
                    return Promise.resolve({ playEffect: 'complete' });
                },
                pulse: function(value, duration) {
                    try { postRumble(value, value, duration || 100); } catch (e) {}
                    return Promise.resolve(true);
                },
                reset: function() { return Promise.resolve(); }
            };
        }

        function wrapActuator(actuator) {
            if (!actuator || actuator.__gsWrapped) return actuator;
            try {
                if (typeof actuator.playEffect === 'function') {
                    var original = actuator.playEffect.bind(actuator);
                    actuator.playEffect = function(type, params) {
                        try {
                            params = params || {};
                            var weak = params.weakMagnitude != null ? params.weakMagnitude : (params.magnitude || 0);
                            var strong = params.strongMagnitude != null ? params.strongMagnitude : (params.magnitude || 0);
                            var start = params.startDelay || 0;
                            var duration = params.duration || 100;
                            setTimeout(function() { postRumble(weak, strong, duration); }, start);
                        } catch (e) {}
                        try { return original(type, params); } catch (e2) {
                            return Promise.resolve({ playEffect: 'complete' });
                        }
                    };
                }
                if (typeof actuator.pulse === 'function') {
                    var origPulse = actuator.pulse.bind(actuator);
                    actuator.pulse = function(value, duration) {
                        try { postRumble(value, value, duration || 100); } catch (e) {}
                        try { return origPulse(value, duration); } catch (e2) { return Promise.resolve(true); }
                    };
                }
                actuator.__gsWrapped = true;
            } catch (e) {}
            return actuator;
        }

        function ensurePad(p) {
            if (!p) return;
            try {
                if (p.vibrationActuator) {
                    wrapActuator(p.vibrationActuator);
                } else {
                    var poly = makePolyActuator();
                    try {
                        Object.defineProperty(p, 'vibrationActuator', { value: poly, configurable: true, writable: true });
                    } catch (e1) {
                        try { p.vibrationActuator = poly; } catch (e2) {}
                    }
                }
                if (p.hapticActuators && p.hapticActuators.length) {
                    for (var j = 0; j < p.hapticActuators.length; j++) {
                        wrapActuator(p.hapticActuators[j]);
                    }
                } else {
                    var list = [p.vibrationActuator || makePolyActuator()];
                    try {
                        Object.defineProperty(p, 'hapticActuators', { value: list, configurable: true, writable: true });
                    } catch (e3) {
                        try { p.hapticActuators = list; } catch (e4) {}
                    }
                }
            } catch (e) {}
        }

        function scanGamepads() {
            try {
                var pads = navigator.getGamepads ? navigator.getGamepads() : [];
                for (var i = 0; i < pads.length; i++) ensurePad(pads[i]);
            } catch (e) {}
        }

        if (!window.__gsRumbleBridge) {
            window.__gsRumbleBridge = true;
            try {
                var originalGet = navigator.getGamepads && navigator.getGamepads.bind(navigator);
                if (originalGet) {
                    navigator.getGamepads = function() {
                        var pads = originalGet();
                        try {
                            for (var i = 0; i < pads.length; i++) ensurePad(pads[i]);
                        } catch (e) {}
                        return pads;
                    };
                }
            } catch (e) {}

            window.addEventListener('gamepadconnected', function() { setTimeout(scanGamepads, 50); });

            try {
                var _pulse = window.navigator && window.navigator.vibrate;
                if (typeof _pulse === 'function') {
                    window.navigator.vibrate = function(pattern) {
                        try {
                            var ms = 80, mag = 0.6;
                            if (typeof pattern === 'number') { ms = pattern; }
                            else if (pattern && pattern.length) { ms = pattern[0] || 80; }
                            postRumble(mag * 0.7, mag, ms);
                        } catch (e) {}
                        try { return _pulse.apply(this, arguments); } catch (e2) { return false; }
                    };
                } else {
                    try {
                        window.navigator.vibrate = function(pattern) {
                            try {
                                var ms = 80, mag = 0.6;
                                if (typeof pattern === 'number') { ms = pattern; }
                                else if (pattern && pattern.length) { ms = pattern[0] || 80; }
                                postRumble(mag * 0.7, mag, ms);
                            } catch (e) {}
                            return true;
                        };
                    } catch (e) {}
                }
            } catch (e) {}

            setInterval(scanGamepads, 1000);
        }
        scanGamepads();
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.websiteDataStore = .default()
        config.processPool = SignInWebViewRepresentable.processPool

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let contentController = config.userContentController

        contentController.addUserScript(WKUserScript(
            source: BetterXCloudInjector.bootstrapJS + "\n" + BetterXCloudInjector.modernUIOverridesJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        // Prefer vibration on in Better xCloud when present.
        var bxPrefs = SessionStore.storedBetterXCloudPrefs()
        if bxPrefs["controller.vibration"] == nil {
            bxPrefs["controller.vibration"] = "true"
        }
        if bxPrefs["native-mfi-controller.vibration"] == nil {
            bxPrefs["native-mfi-controller.vibration"] = "true"
        }
        let prefsJS = SessionStore.betterXCloudPrefsJS(bxPrefs, reloadIfXbox: false)
        contentController.addUserScript(WKUserScript(
            source: prefsJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        if let scriptSource = BetterXCloudInjector.shared.currentScriptSource() {
            contentController.addUserScript(WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        contentController.add(context.coordinator, name: "gamestreamBridge")

        let bridgeJS = """
        (function() {
            function notify() {
                try {
                    const href = location.href || '';
                    const streaming =
                        /\\/play\\/launch|\\/launch\\/|\\/launch\\?|\\/stream\\/|\\/streaming/i.test(href) &&
                        href.toLowerCase().indexOf('/play/games') === -1;
                    window.webkit.messageHandlers.gamestreamBridge.postMessage({
                        type: 'url',
                        href: href,
                        streaming: streaming,
                        title: document.title || ''
                    });
                } catch (e) {}
            }
            notify();
            const pushState = history.pushState;
            history.pushState = function() {
                pushState.apply(this, arguments);
                setTimeout(notify, 50);
            };
            const replaceState = history.replaceState;
            history.replaceState = function() {
                replaceState.apply(this, arguments);
                setTimeout(notify, 50);
            };
            window.addEventListener('popstate', function() { setTimeout(notify, 50); });
            window.addEventListener('hashchange', function() { setTimeout(notify, 50); });
        })();
        """
        contentController.addUserScript(WKUserScript(
            source: bridgeJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        contentController.addUserScript(WKUserScript(
            source: Self.rumbleBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        contentController.addUserScript(WKUserScript(
            source: Self.rumbleBridgeJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        contentController.addUserScript(WKUserScript(
            source: BetterXCloudInjector.streamIsolationJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = MicrosoftAuth.safariUserAgent
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.isOpaque = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false

        context.coordinator.webView = webView
        BetterXCloudInjector.shared.ensureInjected(into: webView)

        if url.absoluteString != "about:blank" {
            webView.load(URLRequest(url: url))
        }
        context.coordinator.lastLoadedURL = url
        context.coordinator.lastReloadNonce = session.reloadNonce

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedURL != url {
            context.coordinator.lastLoadedURL = url
            if url.absoluteString == "about:blank" {
                uiView.stopLoading()
                ControllerRumble.shared.teardown()
            } else {
                uiView.load(URLRequest(url: url))
            }
        }

        if context.coordinator.lastReloadNonce != session.reloadNonce {
            context.coordinator.lastReloadNonce = session.reloadNonce
            uiView.reload()
        }

        if let js = session.pendingJavaScript, !js.isEmpty {
            context.coordinator.runPendingJS(js, in: uiView)
            DispatchQueue.main.async {
                if session.pendingJavaScript == js {
                    session.pendingJavaScript = nil
                }
            }
        }

        if context.coordinator.lastRefreshToken != session.betterXCloudRefreshToken {
            context.coordinator.lastRefreshToken = session.betterXCloudRefreshToken
            BetterXCloudInjector.shared.invalidateCache()
            BetterXCloudInjector.shared.ensureInjected(into: uiView)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastLoadedURL: URL?
        var lastRefreshToken: Int = 0
        var lastReloadNonce: Int = 0
        weak var webView: WKWebView?
        private weak var session: SessionStore?

        init(session: SessionStore) {
            self.session = session
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "gamestreamBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "url":
                if let href = body["href"] as? String {
                    NotificationCenter.default.post(name: .playerStreamPageReached, object: nil)
                    if let streaming = body["streaming"] as? Bool, streaming {
                        NotificationCenter.default.post(name: .playerStreamPageReached, object: href)
                    }
                    if let url = URL(string: href) {
                        Task { @MainActor in
                            self.session?.updateFromWebURL(url, pageTitle: body["title"] as? String)
                        }
                    }
                }
            case "rumble":
                let weakMag = floatValue(body["weak"])
                let strongMag = floatValue(body["strong"])
                let duration = doubleValue(body["duration"], fallback: 80)
                Task { @MainActor in
                    ControllerRumble.shared.play(
                        weak: weakMag,
                        strong: strongMag,
                        durationMs: duration
                    )
                }
            default:
                break
            }
        }

        private func floatValue(_ any: Any?) -> Float {
            if let f = any as? Float { return f }
            if let d = any as? Double { return Float(d) }
            if let n = any as? NSNumber { return n.floatValue }
            return 0
        }

        private func doubleValue(_ any: Any?, fallback: Double) -> Double {
            if let d = any as? Double { return d }
            if let f = any as? Float { return Double(f) }
            if let n = any as? NSNumber { return n.doubleValue }
            return fallback
        }

        func runPendingJS(_ js: String, in webView: WKWebView) {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            BetterXCloudInjector.shared.ensureInjected(into: webView)
            webView.evaluateJavaScript(XboxCloudWebView.rumbleBridgeJS, completionHandler: nil)
            if let url = webView.url {
                Task { @MainActor in
                    self.session?.updateFromWebURL(url, pageTitle: webView.title)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            NotificationCenter.default.post(name: .webViewDidFail, object: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            NotificationCenter.default.post(name: .webViewDidFail, object: error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let requestURL = navigationAction.request.url,
               let https = MicrosoftAuth.httpsXboxURL(from: requestURL) {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: https))
                return
            }
            decisionHandler(.allow)
        }
    }
}

extension Notification.Name {
    static let playerStreamPageReached = Notification.Name("playerStreamPageReached")
}
