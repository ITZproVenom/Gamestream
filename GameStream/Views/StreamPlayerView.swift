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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Bootstrap + modern UI overrides (always on)
        let bootstrap = WKUserScript(
            source: BetterXCloudInjector.bootstrapJS + "\n" + BetterXCloudInjector.modernUIOverridesJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(bootstrap)

        // Full Better xCloud script
        BetterXCloudInjector.shared.prepareUserScript { script in
            if let script {
                config.userContentController.addUserScript(script)
            }
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black

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
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedURL: URL?
        weak var webView: WKWebView?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            BetterXCloudInjector.shared.ensureInjected(into: webView)
            // Re-apply modern UI after page settles
            webView.evaluateJavaScript(BetterXCloudInjector.modernUIOverridesJS, completionHandler: nil)
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

// MARK: - Better xCloud Injector + Modern UI

final class BetterXCloudInjector {
    static let shared = BetterXCloudInjector()

    private let scriptURL = URL(string: "https://github.com/redphx/better-xcloud/releases/latest/download/better-xcloud.user.js")!
    private let cacheKey = "BetterXCloud.Script.v1"
    private let cacheDateKey = "BetterXCloud.Script.Date"
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

    /// Modern CSS + small JS overrides to make Better xCloud UI feel current
    static let modernUIOverridesJS = """
    (function() {
        if (window.__bxModernUI) return;
        window.__bxModernUI = true;

        const css = `
        /* ===== Better xCloud modern overrides (GameStream) ===== */

        /* Main settings / dialog panels */
        [class*="bx-"],
        [id*="bx-"],
        .bx-settings,
        .bx-dialog,
        .bx-menu,
        .bx-stats-bar,
        .bx-toast {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif !important;
            -webkit-font-smoothing: antialiased !important;
        }

        /* Glass-like panels */
        .bx-settings,
        .bx-dialog,
        [class*="bx-modal"],
        [class*="bx-panel"] {
            background: rgba(22, 22, 24, 0.82) !important;
            backdrop-filter: blur(28px) saturate(160%) !important;
            -webkit-backdrop-filter: blur(28px) saturate(160%) !important;
            border: 1px solid rgba(255,255,255,0.10) !important;
            border-radius: 18px !important;
            box-shadow: 0 12px 40px rgba(0,0,0,0.45) !important;
            color: #f5f5f7 !important;
        }

        /* Buttons */
        .bx-settings button,
        .bx-dialog button,
        [class*="bx-"] button {
            border-radius: 12px !important;
            font-weight: 600 !important;
            letter-spacing: -0.01em !important;
            transition: transform 0.15s ease, opacity 0.15s ease !important;
        }

        .bx-settings button:active,
        .bx-dialog button:active {
            transform: scale(0.97) !important;
        }

        /* Stream stats bar */
        .bx-stats-bar,
        [class*="bx-stats"] {
            background: rgba(16, 16, 18, 0.75) !important;
            backdrop-filter: blur(20px) saturate(150%) !important;
            -webkit-backdrop-filter: blur(20px) saturate(150%) !important;
            border: 1px solid rgba(255,255,255,0.08) !important;
            border-radius: 14px !important;
            padding: 6px 12px !important;
            font-size: 12px !important;
            font-variant-numeric: tabular-nums !important;
            letter-spacing: 0.02em !important;
            box-shadow: 0 6px 20px rgba(0,0,0,0.35) !important;
        }

        /* Server / region button near profile */
        [class*="bx-server"],
        [class*="bx-region"] {
            border-radius: 12px !important;
            background: rgba(255,255,255,0.08) !important;
            border: 1px solid rgba(255,255,255,0.10) !important;
            backdrop-filter: blur(12px) !important;
            -webkit-backdrop-filter: blur(12px) !important;
        }

        /* Toasts */
        .bx-toast,
        [class*="bx-toast"] {
            background: rgba(28, 28, 30, 0.9) !important;
            backdrop-filter: blur(24px) !important;
            -webkit-backdrop-filter: blur(24px) !important;
            border-radius: 14px !important;
            border: 1px solid rgba(255,255,255,0.08) !important;
            box-shadow: 0 8px 28px rgba(0,0,0,0.4) !important;
        }

        /* Scrollbars inside panels */
        .bx-settings ::-webkit-scrollbar,
        .bx-dialog ::-webkit-scrollbar {
            width: 6px !important;
            height: 6px !important;
        }
        .bx-settings ::-webkit-scrollbar-thumb,
        .bx-dialog ::-webkit-scrollbar-thumb {
            background: rgba(255,255,255,0.18) !important;
            border-radius: 10px !important;
        }

        /* Slightly tighter spacing */
        .bx-settings,
        .bx-dialog {
            padding: 16px !important;
        }
        `;

        const style = document.createElement('style');
        style.id = 'gamestream-bx-modern';
        style.textContent = css;
        (document.head || document.documentElement).appendChild(style);

        // Keep re-applying in case Better xCloud recreates nodes
        const observer = new MutationObserver(() => {
            if (!document.getElementById('gamestream-bx-modern')) {
                (document.head || document.documentElement).appendChild(style);
            }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
    })();
    """

    private init() {
        if let cached = UserDefaults.standard.string(forKey: cacheKey) {
            cachedScript = cached
        }
    }

    func prepareUserScript(completion: @escaping (WKUserScript?) -> Void) {
        if let script = cachedScript, !script.isEmpty {
            let userScript = WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            completion(userScript)
            refreshIfNeeded()
            return
        }

        fetchScript { [weak self] source in
            guard let self, let source, !source.isEmpty else {
                completion(nil)
                return
            }
            let userScript = WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            completion(userScript)
        }
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
                  let source = String(data: data, encoding: .utf8),
                  source.count > 1000 else {
                DispatchQueue.main.async { completion(self?.cachedScript) }
                return
            }

            self.cachedScript = source
            UserDefaults.standard.set(source, forKey: self.cacheKey)
            UserDefaults.standard.set(Date(), forKey: self.cacheDateKey)

            DispatchQueue.main.async {
                completion(source)
            }
        }.resume()
    }
}

extension Notification.Name {
    static let webViewLoadingChanged = Notification.Name("webViewLoadingChanged")
    static let webViewDidFail = Notification.Name("webViewDidFail")
}
