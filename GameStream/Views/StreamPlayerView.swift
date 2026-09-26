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
        .onAppear {
            ExperimentalControllerInput.shared.start()
        }
        .onDisappear {
            ExperimentalControllerInput.shared.stop()
        }
    }
}

struct XboxCloudWebView: UIViewRepresentable {
    @Binding var url: URL
    @EnvironmentObject var session: SessionStore

    /// Forwards Xbox Cloud FourMotorRumble packets from the WebRTC "input"
    /// RTCDataChannel to native GCDeviceHaptics. Packet layout matches Better
    /// xCloud DeviceVibrationManager exactly. Must run at document-start so
    /// createDataChannel is wrapped before xCloud/Better xCloud open the stream.
    static let rumbleBridgeJS = #"""
    (function() {
        if (window.__gsRumbleBridgeV3) return;
        window.__gsRumbleBridgeV3 = true;

        var lastPacketAt = 0;
        var lastLogAt = 0;
        var hooked = typeof WeakSet !== 'undefined' ? new WeakSet() : null;
        var inputFound = false;

        function post(payload) {
            try { window.webkit.messageHandlers.gamestreamBridge.postMessage(payload); } catch (e) {}
        }

        function log(event, extra) {
            try {
                var now = Date.now();
                if (event === 'packet' && now - lastLogAt < 1000) return;
                if (event === 'packet') lastLogAt = now;
                extra = extra || {};
                extra.type = 'rumbleLog';
                extra.event = event;
                post(extra);
            } catch (e) {}
        }

        function sendMotors(data) {
            var left = Number(data.leftMotorPercent) || 0;
            var right = Number(data.rightMotorPercent) || 0;
            var lt = Number(data.leftTriggerMotorPercent) || 0;
            var rt = Number(data.rightTriggerMotorPercent) || 0;
            var duration = Number(data.durationMs) || 0;
            var index = Number(data.gamepadIndex) || 0;
            lastPacketAt = (typeof performance !== 'undefined' ? performance.now() : Date.now());
            log('packet', {
                leftMotorPercent: left,
                rightMotorPercent: right,
                leftTriggerMotorPercent: lt,
                rightTriggerMotorPercent: rt,
                durationMs: duration
            });
            post({
                type: 'rumble',
                leftMotorPercent: left,
                rightMotorPercent: right,
                leftTriggerMotorPercent: lt,
                rightTriggerMotorPercent: rt,
                durationMs: duration,
                gamepadIndex: index
            });
        }

        // Copied from better-xcloud DeviceVibrationManager.onMessage.
        function parseVibration(buffer) {
            try {
                if (!(buffer instanceof ArrayBuffer)) return;
                var dataView = new DataView(buffer);
                var offset = 0;
                var messageType;
                if (dataView.byteLength === 13) {
                    messageType = dataView.getUint16(offset, true);
                    offset += 2;
                } else {
                    messageType = dataView.getUint8(offset);
                    offset += 1;
                }
                if (!(messageType & 128)) return;
                var vibrationType = dataView.getUint8(offset);
                offset += 1;
                if (vibrationType !== 0) return;

                var data = {};
                var keys = [
                    ['gamepadIndex', 8],
                    ['leftMotorPercent', 8],
                    ['rightMotorPercent', 8],
                    ['leftTriggerMotorPercent', 8],
                    ['rightTriggerMotorPercent', 8],
                    ['durationMs', 16]
                ];
                for (var i = 0; i < keys.length; i++) {
                    var bits = keys[i][1];
                    if (bits === 16) {
                        if (offset + 2 > dataView.byteLength) return;
                        data[keys[i][0]] = dataView.getUint16(offset, true);
                        offset += 2;
                    } else {
                        if (offset + 1 > dataView.byteLength) return;
                        data[keys[i][0]] = dataView.getUint8(offset);
                        offset += 1;
                    }
                }
                sendMotors(data);
            } catch (e) {
                log('parseError', { message: String(e) });
            }
        }

        function inspectMessageEvent(event) {
            try {
                if (!event) return;
                if (event.data instanceof ArrayBuffer) {
                    parseVibration(event.data);
                } else if (typeof Blob !== 'undefined' && event.data instanceof Blob) {
                    event.data.arrayBuffer().then(parseVibration).catch(function() {});
                }
            } catch (e) {}
        }

        function hookInputChannel(channel, source) {
            try {
                if (!channel || channel.label !== 'input') return;
                if (hooked) {
                    if (hooked.has(channel)) return;
                    hooked.add(channel);
                }
                if (!inputFound) {
                    inputFound = true;
                    log('inputChannel', { source: source || 'unknown', label: String(channel.label || '') });
                }
                channel.addEventListener('message', inspectMessageEvent);
            } catch (e) {
                log('hookError', { message: String(e) });
            }
        }

        try {
            if (window.RTCPeerConnection && RTCPeerConnection.prototype.createDataChannel) {
                var nativeCreate = RTCPeerConnection.prototype.createDataChannel;
                RTCPeerConnection.prototype.createDataChannel = function() {
                    var channel = nativeCreate.apply(this, arguments);
                    try { hookInputChannel(channel, 'createDataChannel'); } catch (e) {}
                    return channel;
                };
            }
        } catch (e) {}

        try {
            var pcProto = window.RTCPeerConnection && RTCPeerConnection.prototype;
            if (pcProto && pcProto.addEventListener) {
                var nativeAdd = pcProto.addEventListener;
                pcProto.addEventListener = function(type, listener, options) {
                    if (type === 'datachannel' && typeof listener === 'function') {
                        var wrapped = function(ev) {
                            try { if (ev && ev.channel) hookInputChannel(ev.channel, 'datachannel'); } catch (e) {}
                            return listener.apply(this, arguments);
                        };
                        return nativeAdd.call(this, type, wrapped, options);
                    }
                    return nativeAdd.call(this, type, listener, options);
                };
            }
        } catch (e) {}

        try {
            var nativeFetch = window.fetch && window.fetch.bind(window);
            if (nativeFetch) {
                window.fetch = function(resource, init) {
                    var url = '';
                    try {
                        if (typeof resource === 'string') url = resource;
                        else if (resource && resource.url) url = resource.url;
                    } catch (e) {}
                    var pending = nativeFetch(resource, init);
                    if (!url || !/\/configuration(\?|$)/.test(url)) return pending;
                    return pending.then(function(response) {
                        return response.clone().text().then(function(text) {
                            try {
                                if (!text) return response;
                                var obj = JSON.parse(text);
                                var overrides = {};
                                try { overrides = JSON.parse(obj.clientStreamingConfigOverrides || '{}') || {}; } catch (err) { overrides = {}; }
                                overrides.inputConfiguration = overrides.inputConfiguration || {};
                                overrides.inputConfiguration.enableVibration = true;
                                obj.clientStreamingConfigOverrides = JSON.stringify(overrides);
                                return new Response(JSON.stringify(obj), {
                                    status: response.status,
                                    statusText: response.statusText,
                                    headers: response.headers
                                });
                            } catch (err) {
                                return response;
                            }
                        }).catch(function() { return response; });
                    });
                };
            }
        } catch (e) {}

        try {
            var originalVibrate = navigator.vibrate ? navigator.vibrate.bind(navigator) : function() { return true; };
            navigator.vibrate = function(pattern) {
                var now = (typeof performance !== 'undefined' ? performance.now() : Date.now());
                if (now - lastPacketAt < 400) return true;
                var duration = 80;
                try {
                    if (typeof pattern === 'number') duration = pattern;
                    else if (pattern && pattern.length) duration = Number(pattern[0]) || 80;
                } catch (e) {}
                if (!duration) {
                    sendMotors({ leftMotorPercent: 0, rightMotorPercent: 0, leftTriggerMotorPercent: 0, rightTriggerMotorPercent: 0, durationMs: 0, gamepadIndex: 0 });
                    return true;
                }
                try { originalVibrate(pattern); } catch (e) {}
                return true;
            };
        } catch (e) {}

        log('bridgeReady', {
            hasRTC: !!window.RTCPeerConnection,
            hasVibrate: typeof navigator.vibrate === 'function'
        });
    })();
    """#

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

        // Install the rumble bridge before Better xCloud so createDataChannel
        // is wrapped before the Xbox Cloud WebRTC "input" channel exists.
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
                let left = firstFloat(body["leftMotorPercent"], body["weak"])
                let right = firstFloat(body["rightMotorPercent"], body["strong"])
                let leftTrigger = floatValue(body["leftTriggerMotorPercent"])
                let rightTrigger = floatValue(body["rightTriggerMotorPercent"])
                let duration = firstDouble(body["durationMs"], body["duration"], fallback: 80)
                Task { @MainActor in
                    ExperimentalControllerInput.shared.playRumble(
                        ControllerRumbleEvent(
                            controllerID: Int(body["gamepadIndex"] as? Int ?? 0),
                            lowFrequency: left,
                            highFrequency: right,
                            leftTrigger: leftTrigger,
                            rightTrigger: rightTrigger,
                            durationMs: duration
                        )
                    )
                }
            case "rumbleLog":
                let event = body["event"] as? String ?? "unknown"
                Task { @MainActor in
                    ControllerRumble.shared.noteNativeLog(event, details: stringify(body))
                }
            default:
                break
            }
        }

        private func floatValue(_ any: Any?) -> Float {
            if let f = any as? Float { return f }
            if let d = any as? Double { return Float(d) }
            if let n = any as? NSNumber { return n.floatValue }
            if let s = any as? String { return Float(s) ?? 0 }
            return 0
        }

        private func firstFloat(_ primary: Any?, _ fallback: Any?) -> Float {
            if primary != nil { return floatValue(primary) }
            return floatValue(fallback)
        }

        private func doubleValue(_ any: Any?, fallback: Double) -> Double {
            if let d = any as? Double { return d }
            if let f = any as? Float { return Double(f) }
            if let n = any as? NSNumber { return n.doubleValue }
            if let s = any as? String, let d = Double(s) { return d }
            return fallback
        }

        private func firstDouble(_ a: Any?, _ b: Any?, fallback: Double) -> Double {
            if a != nil { return doubleValue(a, fallback: fallback) }
            return doubleValue(b, fallback: fallback)
        }

        private func stringify(_ body: [String: Any]) -> String {
            let keys = body.keys.sorted()
            return keys.compactMap { key in
                if key == "type" || key == "event" { return nil }
                return "\(key)=\(body[key] ?? "")"
            }.joined(separator: " ")
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
