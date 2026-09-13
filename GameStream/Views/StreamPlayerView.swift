import SwiftUI
import WebKit

struct StreamPlayerView: View {
    var body: some View {
        XboxCloudWebView(url: .constant(URL(string: "https://www.xbox.com/play")!))
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct XboxCloudWebView: UIViewRepresentable {
    @Binding var url: URL
    @EnvironmentObject var session: SessionStore

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
        // Same process pool as sign-in so auth cookies are shared
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
            setInterval(notify, 1500);
        })();
        """
        contentController.addUserScript(WKUserScript(
            source: bridgeJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.isOpaque = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false

        context.coordinator.webView = webView
        BetterXCloudInjector.shared.ensureInjected(into: webView)

        webView.load(URLRequest(url: url))
        context.coordinator.lastLoadedURL = url
        context.coordinator.lastReloadNonce = session.reloadNonce

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Only load when the *app* changed the destination URL
        if context.coordinator.lastLoadedURL != url {
            context.coordinator.lastLoadedURL = url
            uiView.load(URLRequest(url: url))
        }

        // Hard reload when user taps refresh (URL may be unchanged)
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

        func runPendingJS(_ js: String, in webView: WKWebView) {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "gamestreamBridge",
                  let body = message.body as? [String: Any] else { return }

            if let href = body["href"] as? String,
               let url = URL(string: href) {
                let title = body["title"] as? String
                Task { @MainActor in
                    // Streaming state only — must not rewrite session.webURL
                    session?.updateFromWebURL(url, pageTitle: title)
                }
            }

            if let streaming = body["streaming"] as? Bool {
                Task { @MainActor in
                    if session?.isStreaming != streaming {
                        session?.isStreaming = streaming
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            BetterXCloudInjector.shared.ensureInjected(into: webView)
            webView.evaluateJavaScript(BetterXCloudInjector.modernUIOverridesJS, completionHandler: nil)

            if let url = webView.url {
                Task { @MainActor in
                    session?.updateFromWebURL(url, pageTitle: webView.title)
                }
            }

            if let js = session?.pendingJavaScript, !js.isEmpty {
                webView.evaluateJavaScript(js, completionHandler: nil)
                Task { @MainActor in
                    session?.pendingJavaScript = nil
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
    }
}
