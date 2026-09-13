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
        config.processPool = Self.sharedProcessPool

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
                    const path = location.pathname || '';
                    const streaming = path.includes('/launch') || path.includes('/play/game');
                    window.webkit.messageHandlers.gamestreamBridge.postMessage({
                        type: 'url',
                        href: href,
                        streaming: streaming
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
            setInterval(notify, 2000);
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

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedURL != url {
            context.coordinator.lastLoadedURL = url
            uiView.load(URLRequest(url: url))
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

    private static let sharedProcessPool = WKProcessPool()

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastLoadedURL: URL?
        var lastRefreshToken: Int = 0
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
                Task { @MainActor in
                    session?.updateFromWebURL(url)
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
                    session?.updateFromWebURL(url)
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

// MARK: - Better xCloud Injector + modern glass UI

final class BetterXCloudInjector {
    static let shared = BetterXCloudInjector()

    private let scriptURL = URL(string: "https://github.com/redphx/better-xcloud/releases/latest/download/better-xcloud.user.js")!
    private let cacheKey = "BetterXCloud.Script.v2"
    private let cacheDateKey = "BetterXCloud.Script.Date.v2"
    private var cachedScript: String?
    private var isFetching = false
    private let lock = NSLock()

    static let bootstrapJS = """
    (function() {
        if (window.__bxInjected) return;
        window.__bxInjected = true;
        window.BetterXCloud = window.BetterXCloud || { injectedBy: 'GameStream' };
    })();
    """

    /// Aggressive modern glass theme for Better xCloud UI (re-applied on every load).
    static let modernUIOverridesJS = """
    (function() {
        const CSS_ID = 'gamestream-bx-modern-v3';
        const css = `
        /* ===== GameStream modern Better xCloud theme ===== */
        html {
            --bx-bg: rgba(16, 16, 18, 0.92);
            --bx-bg-soft: rgba(28, 28, 32, 0.88);
            --bx-border: rgba(255,255,255,0.10);
            --bx-text: #f5f5f7;
            --bx-muted: rgba(255,255,255,0.55);
            --bx-accent: #8b7cff;
            --bx-radius: 18px;
        }

        [class*="bx-"], [id*="bx-"],
        .bx-settings, .bx-dialog, .bx-menu, .bx-stats-bar, .bx-toast,
        [class*="BxSettings"], [class*="BxDialog"], [class*="BxMenu"] {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif !important;
            -webkit-font-smoothing: antialiased !important;
            color: var(--bx-text) !important;
        }

        /* Main panels / settings / dialogs */
        .bx-settings,
        .bx-dialog,
        [class*="bx-modal"],
        [class*="bx-panel"],
        [class*="bx-settings"],
        [class*="BxSettings"],
        [class*="bx-overlay"] > div,
        div[class*="bx-"][class*="dialog"],
        div[class*="bx-"][class*="settings"] {
            background: var(--bx-bg) !important;
            backdrop-filter: blur(40px) saturate(180%) !important;
            -webkit-backdrop-filter: blur(40px) saturate(180%) !important;
            border: 1px solid var(--bx-border) !important;
            border-radius: var(--bx-radius) !important;
            box-shadow: 0 20px 60px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.06) !important;
            color: var(--bx-text) !important;
            padding: 16px !important;
        }

        /* Setting rows */
        [class*="bx-"] label,
        [class*="bx-setting"],
        [class*="bx-row"],
        .bx-settings > div,
        .bx-dialog > div {
            border-color: rgba(255,255,255,0.06) !important;
        }

        /* Buttons */
        [class*="bx-"] button,
        .bx-settings button,
        .bx-dialog button {
            border-radius: 12px !important;
            font-weight: 600 !important;
            letter-spacing: -0.01em !important;
            border: 1px solid rgba(255,255,255,0.08) !important;
            background: rgba(255,255,255,0.08) !important;
            color: var(--bx-text) !important;
            transition: transform 0.12s ease, background 0.12s ease !important;
            padding: 8px 14px !important;
        }
        [class*="bx-"] button:active,
        .bx-settings button:active {
            transform: scale(0.97) !important;
            background: rgba(255,255,255,0.14) !important;
        }
        [class*="bx-"] button[class*="primary"],
        [class*="bx-"] button.primary {
            background: linear-gradient(180deg, #9b8cff, #6d5efc) !important;
            border-color: transparent !important;
        }

        /* Inputs / selects */
        [class*="bx-"] input,
        [class*="bx-"] select,
        [class*="bx-"] textarea {
            background: rgba(255,255,255,0.06) !important;
            border: 1px solid rgba(255,255,255,0.10) !important;
            border-radius: 12px !important;
            color: var(--bx-text) !important;
            padding: 8px 12px !important;
        }

        /* Tabs / section headers */
        [class*="bx-"] [class*="tab"],
        [class*="bx-"] [class*="Tab"] {
            border-radius: 10px !important;
            font-weight: 600 !important;
        }

        /* Stream stats HUD */
        .bx-stats-bar,
        [class*="bx-stats"],
        [class*="BxStats"],
        [id*="bx-stats"] {
            background: rgba(10, 10, 12, 0.78) !important;
            backdrop-filter: blur(28px) saturate(180%) !important;
            -webkit-backdrop-filter: blur(28px) saturate(180%) !important;
            border: 1px solid rgba(255,255,255,0.10) !important;
            border-radius: 16px !important;
            padding: 8px 12px !important;
            font-size: 11px !important;
            font-weight: 600 !important;
            font-variant-numeric: tabular-nums !important;
            letter-spacing: 0.03em !important;
            color: rgba(255,255,255,0.92) !important;
            box-shadow: 0 10px 32px rgba(0,0,0,0.45) !important;
            display: flex !important;
            flex-wrap: wrap !important;
            gap: 6px !important;
            align-items: center !important;
        }
        .bx-stats-bar > *,
        [class*="bx-stats"] > * {
            background: rgba(255,255,255,0.07) !important;
            border-radius: 8px !important;
            padding: 3px 8px !important;
            border: 1px solid rgba(255,255,255,0.05) !important;
        }

        /* Server / region button near profile */
        [class*="bx-server"],
        [class*="bx-region"],
        button[class*="bx-"][class*="server"],
        a[class*="bx-"][class*="server"] {
            border-radius: 14px !important;
            background: rgba(255,255,255,0.10) !important;
            border: 1px solid rgba(255,255,255,0.12) !important;
            backdrop-filter: blur(16px) !important;
            -webkit-backdrop-filter: blur(16px) !important;
            font-weight: 600 !important;
            box-shadow: 0 4px 16px rgba(0,0,0,0.25) !important;
        }

        /* Toasts */
        .bx-toast,
        [class*="bx-toast"] {
            background: rgba(20, 20, 22, 0.94) !important;
            backdrop-filter: blur(32px) !important;
            -webkit-backdrop-filter: blur(32px) !important;
            border-radius: 16px !important;
            border: 1px solid rgba(255,255,255,0.10) !important;
            box-shadow: 0 12px 36px rgba(0,0,0,0.5) !important;
            color: var(--bx-text) !important;
        }

        /* Scrollbars */
        [class*="bx-"]::-webkit-scrollbar { width: 6px !important; height: 6px !important; }
        [class*="bx-"]::-webkit-scrollbar-thumb {
            background: rgba(255,255,255,0.18) !important;
            border-radius: 10px !important;
        }

        /* Secondary text */
        [class*="bx-"] small,
        [class*="bx-"] .note,
        [class*="bx-"] [class*="note"],
        [class*="bx-"] [class*="desc"] {
            color: var(--bx-muted) !important;
        }
        `;

        function apply() {
            let style = document.getElementById(CSS_ID);
            if (!style) {
                style = document.createElement('style');
                style.id = CSS_ID;
                (document.head || document.documentElement).appendChild(style);
            }
            if (style.textContent !== css) style.textContent = css;
        }

        apply();

        // Keep re-applying as BX recreates DOM
        const obs = new MutationObserver(function() { apply(); });
        obs.observe(document.documentElement, { childList: true, subtree: true });
        setInterval(apply, 2000);
    })();
    """

    private init() {
        if let cached = UserDefaults.standard.string(forKey: cacheKey) {
            cachedScript = Self.stripUserScriptHeader(cached)
        }
    }

    func preload() {
        if cachedScript == nil || cachedScript?.isEmpty == true {
            fetchScript { _ in }
        } else {
            refreshIfNeeded()
        }
    }

    func currentScriptSource() -> String? { cachedScript }

    func invalidateCache() {
        lock.lock()
        cachedScript = nil
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheDateKey)
    }

    func ensureInjected(into webView: WKWebView) {
        if let script = cachedScript, !script.isEmpty {
            webView.evaluateJavaScript(script, completionHandler: nil)
            webView.evaluateJavaScript(Self.modernUIOverridesJS, completionHandler: nil)
            return
        }

        fetchScript { [weak webView] source in
            guard let webView, let source, !source.isEmpty else { return }
            DispatchQueue.main.async {
                webView.evaluateJavaScript(source, completionHandler: nil)
                webView.evaluateJavaScript(Self.modernUIOverridesJS, completionHandler: nil)
            }
        }
    }

    private static func stripUserScriptHeader(_ source: String) -> String {
        if let end = source.range(of: "// ==/UserScript==") {
            return String(source[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return source
    }

    private func refreshIfNeeded() {
        let lastDate = UserDefaults.standard.object(forKey: cacheDateKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(lastDate) > 7 * 24 * 3600 {
            fetchScript { _ in }
        }
    }

    private func fetchScript(completion: @escaping (String?) -> Void) {
        lock.lock()
        if isFetching {
            lock.unlock()
            completion(cachedScript)
            return
        }
        isFetching = true
        lock.unlock()

        var request = URLRequest(url: scriptURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer {
                self?.lock.lock()
                self?.isFetching = false
                self?.lock.unlock()
            }

            guard let self,
                  error == nil,
                  let data,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  var source = String(data: data, encoding: .utf8),
                  source.count > 1000 else {
                DispatchQueue.main.async { completion(self?.cachedScript) }
                return
            }

            source = Self.stripUserScriptHeader(source)
            self.cachedScript = source
            UserDefaults.standard.set(source, forKey: self.cacheKey)
            UserDefaults.standard.set(Date(), forKey: self.cacheDateKey)

            DispatchQueue.main.async { completion(source) }
        }.resume()
    }
}

extension Notification.Name {
    static let webViewLoadingChanged = Notification.Name("webViewLoadingChanged")
    static let webViewDidFail = Notification.Name("webViewDidFail")
}
