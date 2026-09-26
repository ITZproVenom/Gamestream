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

    var body: some View {
        ZStack(alignment: .top) {
            XboxCloudWebView(url: $session.webURL)
                .ignoresSafeArea(edges: .all)

            if isLoading {
                PlayLoadingView(title: session.currentGame?.title ?? "")
                    .transition(.opacity)
                    .zIndex(2)
            }

            HStack(spacing: 8) {
                Button {
                    session.exitStreamToHub()
                } label: {
                    Text("Exit")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)

                Button {
                    session.returnToHub()
                } label: {
                    Text("Hub")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .webViewDidFail)) { note in
            errorMessage = note.object as? String
            isLoading = false
        }
        .onDisappear {
            ControllerRumble.shared.teardown()
        }
    }
}

struct XboxCloudWebView: UIViewRepresentable {
    @Binding var url: URL
    @EnvironmentObject var session: SessionStore

    /// Forwards Web Gamepad / Better xCloud vibration calls to native GCDeviceHaptics.
    static let rumbleBridgeJS = """
    (function() {
        if (window.__gsRumbleBridgeV2) return;
        window.__gsRumbleBridgeV2 = true;

        function send(weak, strong, duration, index) {
            try {
                var w = Math.max(0, Math.min(1, Number(weak) || 0));
                var s = Math.max(0, Math.min(1, Number(strong) || 0));
                var d = Math.max(0, Math.min(2500, Number(duration) || 0));
                if (w === 0 && s === 0) return;
                window.webkit.messageHandlers.gamestreamBridge.postMessage({
                    type: "rumble",
                    weak: w,
                    strong: s,
                    duration: d || 80,
                    gamepadIndex: Number(index) || 0
                });
            } catch (e) {}
        }

        // Xbox Cloud sends vibration commands on its WebRTC input data channel.
        // Better xCloud parses those packets in DeviceVibrationManager. WKWebView
        // on iOS does not expose Gamepad vibrationActuator, so intercept the
        // input channel directly before Better xCloud consumes the message.
        function parseVibration(buffer) {
            try {
                if (!(buffer instanceof ArrayBuffer)) return;
                var view = new DataView(buffer);
                var offset = 0;
                var messageType;
                if (view.byteLength === 13) {
                    if (view.byteLength < 2) return;
                    messageType = view.getUint16(0, true);
                    offset = 2;
                } else {
                    if (view.byteLength < 1) return;
                    messageType = view.getUint8(0);
                    offset = 1;
                }
                if (!(messageType & 128) || view.byteLength < offset + 8) return;

                var vibrationType = view.getUint8(offset);
                offset += 1;
                if (vibrationType !== 0) return;

                var gamepadIndex = view.getUint8(offset); offset += 1;
                var left = view.getUint8(offset) / 100; offset += 1;
                var right = view.getUint8(offset) / 100; offset += 1;
                offset += 1; // left trigger motor
                offset += 1; // right trigger motor
                if (offset + 2 > view.byteLength) return;
                var duration = view.getUint16(offset, true);
                send(left, right, duration, gamepadIndex);
            } catch (e) {}
        }

        function inspectMessageEvent(event) {
            try {
                if (!event) return;
                if (event.data instanceof ArrayBuffer) {
                    parseVibration(event.data);
                } else if (typeof Blob !== "undefined" && event.data instanceof Blob) {
                    event.data.arrayBuffer().then(parseVibration).catch(function() {});
                }
            } catch (e) {}
        }

        // Patch addEventListener so DeviceVibrationManager receives the normal
        // event while the native bridge gets a copy of the exact packet.
        try {
            var proto = window.RTCDataChannel && window.RTCDataChannel.prototype;
            if (proto && proto.addEventListener) {
                var originalAdd = proto.addEventListener;
                var originalRemove = proto.removeEventListener;
                var wrappers = new WeakMap();

                proto.addEventListener = function(type, listener, options) {
                    if (type !== "message" || typeof listener !== "function") {
                        return originalAdd.call(this, type, listener, options);
                    }
                    var channel = this;
                    var wrapped = wrappers.get(listener);
                    if (!wrapped) {
                        wrapped = function(event) {
                            try {
                                if (channel && channel.label === "input") inspectMessageEvent(event);
                            } catch (e) {}
                            return listener.call(this, event);
                        };
                        wrappers.set(listener, wrapped);
                    }
                    return originalAdd.call(this, type, wrapped, options);
                };

                if (originalRemove) {
                    proto.removeEventListener = function(type, listener, options) {
                        if (type === "message" && typeof listener === "function") {
                            var wrapped = wrappers.get(listener);
                            if (wrapped) return originalRemove.call(this, type, wrapped, options);
                        }
                        return originalRemove.call(this, type, listener, options);
                    };
                }
            }
        } catch (e) {}

        // Also support code that assigns channel.onmessage directly.
        try {
            var channelProto = window.RTCDataChannel && window.RTCDataChannel.prototype;
            if (channelProto) {
                var descriptor = Object.getOwnPropertyDescriptor(channelProto, "onmessage");
                if (descriptor && descriptor.set && descriptor.get) {
                    var nativeSet = descriptor.set;
                    var nativeGet = descriptor.get;
                    var handlerMap = new WeakMap();
                    Object.defineProperty(channelProto, "onmessage", {
                        configurable: descriptor.configurable,
                        enumerable: descriptor.enumerable,
                        get: function() { return nativeGet.call(this); },
                        set: function(handler) {
                            if (typeof handler !== "function") return nativeSet.call(this, handler);
                            var wrapped = handlerMap.get(handler);
                            if (!wrapped) {
                                wrapped = function(event) {
                                    try { if (this.label === "input") inspectMessageEvent(event); } catch (e) {}
                                    return handler.call(this, event);
                                };
                                handlerMap.set(handler, wrapped);
                            }
                            return nativeSet.call(this, wrapped);
                        }
                    });
                }
            }
        } catch (e) {}

        // Fallback: Better xCloud also exposes these vibration calls when WebKit
        // supports device vibration. Redirect them to the controller instead of
        // vibrating the phone.
        try {
            var vibrate = navigator.vibrate && navigator.vibrate.bind(navigator);
            if (vibrate) {
                navigator.vibrate = function(pattern) {
                    var duration = 80;
                    try {
                        if (typeof pattern === "number") duration = pattern;
                        else if (pattern && pattern.length) duration = Number(pattern[0]) || 80;
                    } catch (e) {}
                    send(0.65, 0.85, duration, 0);
                    return true;
                };
            }
        } catch (e) {}

        window.__gsNativeRumble = send;
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

        // Install the rumble/data-channel bridge before Better xCloud starts so its
        // input-channel listener is wrapped before the first streaming message.
        contentController.add(context.coordinator, name: "gamestreamBridge")
        contentController.addUserScript(WKUserScript(
            source: Self.rumbleBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

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
        // Better xCloud's device-vibration manager reads the Xbox input
        // WebRTC data channel. Force that feature on; the bridge above redirects
        // its output to the physical controller instead of the phone vibrator.
        bxPrefs["deviceVibration.mode"] = "on"
        if bxPrefs["deviceVibration.intensity"] == nil {
            bxPrefs["deviceVibration.intensity"] = "100"
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
        // Re-run once after the page is constructed in case WebKit replaced
        // a prototype while the page booted. The bridge is idempotent.
        contentController.addUserScript(WKUserScript(
            source: Self.rumbleBridgeJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
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
