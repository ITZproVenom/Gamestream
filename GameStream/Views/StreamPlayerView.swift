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

        // Always inject Better xCloud
        BetterXCloudInjector.shared.prepareUserScript { script in
            if let script {
                config.userContentController.addUserScript(script)
            }
        }

        // Also inject a small early bootstrap so features appear as soon as possible
        let bootstrap = WKUserScript(
            source: BetterXCloudInjector.bootstrapJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(bootstrap)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black

        // Ensure script is injected even if the async prepare finishes after creation
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
            // Re-ensure Better xCloud is present after navigation
            BetterXCloudInjector.shared.ensureInjected(into: webView)
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

// MARK: - Better xCloud Injector (always-on)

final class BetterXCloudInjector {
    static let shared = BetterXCloudInjector()

    private let scriptURL = URL(string: "https://github.com/redphx/better-xcloud/releases/latest/download/better-xcloud.user.js")!
    private let cacheKey = "BetterXCloud.Script.v1"
    private let cacheDateKey = "BetterXCloud.Script.Date"
    private var cachedScript: String?
    private var isFetching = false
    private let lock = NSLock()

    /// Lightweight bootstrap that runs at document-start.
    /// It loads the full Better xCloud script if it hasn't been injected yet.
    static let bootstrapJS = """
    (function() {
        if (window.__bxInjected) return;
        window.__bxInjected = true;

        // Placeholder so the page knows Better xCloud is expected
        window.BetterXCloud = window.BetterXCloud || { injectedBy: 'GameStream' };

        // The full script will be injected by the native side via WKUserScript
        // or evaluateJavaScript. This bootstrap just marks the page.
    })();
    """

    private init() {
        // Load from cache immediately if available
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
            // Refresh in background if older than 7 days
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
        guard let script = cachedScript, !script.isEmpty else {
            // Try to fetch then inject
            fetchScript { [weak webView] source in
                guard let webView, let source, !source.isEmpty else { return }
                DispatchQueue.main.async {
                    webView.evaluateJavaScript(source, completionHandler: nil)
                }
            }
            return
        }

        // Inject via evaluateJavaScript as a reliable fallback
        // (WKUserScript handles the primary path)
        webView.evaluateJavaScript("""
            (function() {
                if (window.__bxFullScriptInjected) return;
                window.__bxFullScriptInjected = true;
            })();
        """, completionHandler: nil)

        // The heavy script is already in the userContentController from prepareUserScript.
        // If it wasn't ready at webview creation time, inject it now.
        webView.evaluateJavaScript(script, completionHandler: nil)
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
            // Return current cache while fetching
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

            // Cache it
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
