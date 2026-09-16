import SwiftUI
import WebKit

/// The player is a real, long-lived browser session dedicated to one game.
///
/// Pressing Play lands it on `xbox.com/play` (the authenticated cloud home).
/// From there, in order, the same WebView:
///   1. renders signed-in (shared cookie store) or drops to login.live.com where
///      the user completes sign-in directly inside the player,
///   2. is advanced to the game's `/play/launch/{slug}/{id}` page once the landing
///      finishes without bouncing to a login host,
///   3. auto-clicks the Play / Play with ads / Resume button (see streamIsolationJS)
///      so the actual stream starts instead of parking on the game page.
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

        let prefsJS = SessionStore.betterXCloudPrefsJS(SessionStore.storedBetterXCloudPrefs(), reloadIfXbox: false)
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
        })();
        """
        contentController.addUserScript(WKUserScript(
            source: bridgeJS,
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
        private var authBounces = 0
        private var landingAdvanceWorkItem: DispatchWorkItem?

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
                    session?.updateFromWebURL(url, pageTitle: title)
                    if Self.isPlayerStreamingPage(url) {
                        NotificationCenter.default.post(name: .playerStreamPageReached, object: nil)
                    } else {
                        scheduleAdvanceFromLanding(ifNeeded: url.absoluteString)
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
            webView.evaluateJavaScript(BetterXCloudInjector.streamIsolationJS, completionHandler: nil)

            if let url = webView.url {
                Task { @MainActor in
                    session?.updateFromWebURL(url, pageTitle: webView.title)
                    if Self.isPlayerStreamingPage(url) {
                        NotificationCenter.default.post(name: .playerStreamPageReached, object: nil)
                    }
                }
            }

            if let js = session?.pendingJavaScript, !js.isEmpty {
                webView.evaluateJavaScript(js, completionHandler: nil)
                Task { @MainActor in
                    session?.pendingJavaScript = nil
                }
            }

            advancePastAuthLanding(webView: webView)
        }

        static func isPlayerStreamingPage(_ url: URL) -> Bool {
            SessionStore.isStreamingURL(url.absoluteString)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            NotificationCenter.default.post(name: .webViewDidFail, object: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            if (error as NSError).code != NSURLErrorCancelled {
                NotificationCenter.default.post(name: .webViewDidFail, object: error.localizedDescription)
            }
        }

        // Real browser: nothing blocks the stream, sign-in, or store navigation.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }

        /// The landing page can settle and then client-side navigate (pushState) to
        /// the cloud dashboard without another didFinish. Debounce an advance so a
        /// settled, non-login xbox.com destination still moves on to the launch page.
        private func scheduleAdvanceFromLanding(ifNeeded current: String) {
            guard session?.isStreaming == true,
                  session?.webURL == MicrosoftAuth.playURL,
                  MicrosoftAuth.isXboxDestination(current),
                  !MicrosoftAuth.isLoginHost(current) else { return }
            landingAdvanceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak session] in
                Task { @MainActor in
                    guard let session, session.isStreaming, session.webURL == MicrosoftAuth.playURL else { return }
                    if let launch = session.currentGame?.launchURL, launch != MicrosoftAuth.playURL {
                        session.webURL = launch
                    }
                }
            }
            landingAdvanceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }

        /// Play opens on xbox.com/play, the auth landing. It renders signed-in when
        /// the shared cookie store has a session, or redirects to login.live.com
        /// where the user signs in inside the same WebView. Once the landing
        /// finishes on an xbox.com page — not a login host — advance to the game
        /// launch page. If a login page appears after advancing (session dropped),
        /// bounce back to the auth landing to re-sign-in, capped so a genuinely
        /// broken account can't loop forever.
        private func advancePastAuthLanding(webView: WKWebView) {
            guard let session else { return }
            guard session.isStreaming else { return }
            guard let current = webView.url?.absoluteString else { return }

            let onLoginHost = MicrosoftAuth.isLoginHost(current)

            if session.webURL == MicrosoftAuth.playURL {
                // Waiting for the landing to render signed-in (or the user to log in).
                if onLoginHost {
                    return
                }
                if let launch = session.currentGame?.launchURL, launch != MicrosoftAuth.playURL {
                    authBounces = 0
                    session.webURL = launch
                    if !session.isSignedIn {
                        MicrosoftAuth.fetchAuthCookies { cookies in
                            Task { @MainActor in
                                if MicrosoftAuth.cookiesIndicateXboxSession(cookies) {
                                    session.markSignedInAfterMicrosoftAuth()
                                }
                            }
                        }
                    }
                }
                return
            }

            if onLoginHost {
                if authBounces < 3 {
                    authBounces += 1
                    session.webURL = MicrosoftAuth.playURL
                }
                return
            }

            authBounces = 0
        }
    }
}

extension Notification.Name {
    static let playerStreamPageReached = Notification.Name("playerStreamPageReached")
}