import Foundation
import WebKit

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

    static let modernUIOverridesJS = """
    (function() {
        const CSS_ID = 'gamestream-bx-modern-v3';
        const css = `
        html {
            --bx-bg: rgba(16, 16, 18, 0.92);
            --bx-border: rgba(255,255,255,0.10);
            --bx-text: #f5f5f7;
            --bx-muted: rgba(255,255,255,0.55);
            --bx-radius: 18px;
        }
        [class*="bx-"], [id*="bx-"],
        .bx-settings, .bx-dialog, .bx-menu, .bx-stats-bar, .bx-toast,
        [class*="BxSettings"], [class*="BxDialog"], [class*="BxMenu"] {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif !important;
            -webkit-font-smoothing: antialiased !important;
            color: var(--bx-text) !important;
        }
        .bx-settings, .bx-dialog,
        [class*="bx-modal"], [class*="bx-panel"], [class*="bx-settings"],
        [class*="BxSettings"], [class*="bx-overlay"] > div {
            background: var(--bx-bg) !important;
            backdrop-filter: blur(40px) saturate(180%) !important;
            -webkit-backdrop-filter: blur(40px) saturate(180%) !important;
            border: 1px solid var(--bx-border) !important;
            border-radius: var(--bx-radius) !important;
            box-shadow: 0 20px 60px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.06) !important;
            color: var(--bx-text) !important;
            padding: 16px !important;
        }
        [class*="bx-"] button, .bx-settings button, .bx-dialog button {
            border-radius: 12px !important;
            font-weight: 600 !important;
            border: 1px solid rgba(255,255,255,0.08) !important;
            background: rgba(255,255,255,0.08) !important;
            color: var(--bx-text) !important;
            padding: 8px 14px !important;
        }
        [class*="bx-"] input, [class*="bx-"] select, [class*="bx-"] textarea {
            background: rgba(255,255,255,0.06) !important;
            border: 1px solid rgba(255,255,255,0.10) !important;
            border-radius: 12px !important;
            color: var(--bx-text) !important;
            padding: 8px 12px !important;
        }
        .bx-stats-bar, [class*="bx-stats"], [class*="BxStats"], [id*="bx-stats"] {
            background: rgba(10, 10, 12, 0.78) !important;
            backdrop-filter: blur(28px) saturate(180%) !important;
            -webkit-backdrop-filter: blur(28px) saturate(180%) !important;
            border: 1px solid rgba(255,255,255,0.10) !important;
            border-radius: 16px !important;
            padding: 8px 12px !important;
            font-size: 11px !important;
            font-weight: 600 !important;
            font-variant-numeric: tabular-nums !important;
            color: rgba(255,255,255,0.92) !important;
            box-shadow: 0 10px 32px rgba(0,0,0,0.45) !important;
            display: flex !important;
            flex-wrap: wrap !important;
            gap: 6px !important;
        }
        .bx-stats-bar > *, [class*="bx-stats"] > * {
            background: rgba(255,255,255,0.07) !important;
            border-radius: 8px !important;
            padding: 3px 8px !important;
        }
        [class*="bx-server"], [class*="bx-region"] {
            border-radius: 14px !important;
            background: rgba(255,255,255,0.10) !important;
            border: 1px solid rgba(255,255,255,0.12) !important;
            font-weight: 600 !important;
        }
        .bx-toast, [class*="bx-toast"] {
            background: rgba(20, 20, 22, 0.94) !important;
            backdrop-filter: blur(32px) !important;
            -webkit-backdrop-filter: blur(32px) !important;
            border-radius: 16px !important;
            border: 1px solid rgba(255,255,255,0.10) !important;
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
    })();
    """

    static let streamIsolationJS = """
    (function() {
        if (window.__gsStreamIsolation) return;
        window.__gsStreamIsolation = true;
        const CSS_ID = 'gamestream-stream-isolation-v1';
        const css = `
        header, footer, nav,
        [class*="Navigation"], [class*="navigation"],
        [class*="NavBar"], [class*="nav-bar"],
        [class*="Footer"], [class*="footer"],
        [class*="Header"], [class*="header"]:not([class*="stream"]):not([class*="Stream"]),
        [data-testid*="nav"], [data-testid*="header"], [data-testid*="footer"],
        [class*="Cookie"], [class*="cookie"],
        [class*="banner"], [class*="Banner"]:not([class*="stream"]),
        [class*="social"], [class*="Social"],
        [class*="upsell"], [class*="Upsell"],
        [class*="marketing"], [class*="Marketing"] {
            display: none !important;
            visibility: hidden !important;
            height: 0 !important;
            max-height: 0 !important;
            overflow: hidden !important;
            pointer-events: none !important;
        }
        html, body {
            background: #000 !important;
            overflow: hidden !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        video, #game-stream, [class*="stream-video"], [class*="StreamVideo"],
        [class*="video-player"], [class*="VideoPlayer"] {
            max-width: 100vw !important;
            max-height: 100vh !important;
            width: 100% !important;
            height: 100% !important;
            object-fit: contain !important;
            background: #000 !important;
        }
        `;
        function applyCss() {
            let style = document.getElementById(CSS_ID);
            if (!style) {
                style = document.createElement('style');
                style.id = CSS_ID;
                (document.head || document.documentElement).appendChild(style);
            }
            if (style.textContent !== css) style.textContent = css;
        }
        applyCss();
        function tryAutoStart() {
            try {
                const href = (location.href || '').toLowerCase();
                if (href.indexOf('/play/launch') === -1 && href.indexOf('/launch/') === -1) return;
                const vids = document.querySelectorAll('video');
                for (const v of vids) {
                    if (v && !v.paused && v.readyState >= 2) return;
                }
                const labels = ['play', 'start', 'resume', 'continue'];
                const nodes = Array.from(document.querySelectorAll('button, a, [role="button"]'));
                for (const el of nodes) {
                    const text = ((el.innerText || el.textContent || el.getAttribute('aria-label') || '') + '').trim().toLowerCase();
                    if (!text || text.length > 40) continue;
                    if (labels.some(l => text === l || text.startsWith(l + ' '))) {
                        el.click();
                        return;
                    }
                }
            } catch (e) {}
        }
        setTimeout(tryAutoStart, 400);
        setTimeout(tryAutoStart, 1200);
        setTimeout(tryAutoStart, 2500);
        setTimeout(tryAutoStart, 4500);
    })();
    """

    private init() {
        if let bundled = Self.loadBundledScript(), !bundled.isEmpty {
            cachedScript = bundled
        }
        if let cached = UserDefaults.standard.string(forKey: cacheKey) {
            let stripped = Self.stripUserScriptHeader(cached)
            if stripped.count > (cachedScript?.count ?? 0) {
                cachedScript = stripped
            }
        }
    }

    /// Offline floor: script shipped inside the IPA so first launch / offline still works.
    private static func loadBundledScript() -> String? {
        let url =
            Bundle.main.url(forResource: "better-xcloud.user", withExtension: "js")
            ?? Bundle.main.url(forResource: "better-xcloud.user", withExtension: "js", subdirectory: nil)
        guard let url, let raw = try? String(contentsOf: url, encoding: .utf8), raw.count > 1000 else {
            return nil
        }
        return stripUserScriptHeader(raw)
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
            webView.evaluateJavaScript(Self.streamIsolationJS, completionHandler: nil)
            return
        }

        fetchScript { [weak webView] source in
            guard let webView, let source, !source.isEmpty else { return }
            DispatchQueue.main.async {
                webView.evaluateJavaScript(source, completionHandler: nil)
                webView.evaluateJavaScript(Self.modernUIOverridesJS, completionHandler: nil)
                webView.evaluateJavaScript(Self.streamIsolationJS, completionHandler: nil)
            }
        }
    }

    private func refreshIfNeeded() {
        let last = UserDefaults.standard.object(forKey: cacheDateKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 86400 {
            fetchScript { _ in }
        }
    }

    private static func stripUserScriptHeader(_ source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        if lines.first?.contains("==UserScript==") == true {
            if let end = lines.firstIndex(where: { $0.contains("==/UserScript==") }) {
                lines = Array(lines.suffix(from: end + 1))
            }
        }
        return lines.joined(separator: "\n")
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
