import Foundation
import WebKit

/// Loads the signed-in Xbox Cloud home page with the shared cookie store and
/// extracts product IDs from the "recently played" / jump-back-in surface so
/// the native GameHub Recents list matches what the user played on Xbox.
@MainActor
final class XboxPlayHistoryService: NSObject, WKNavigationDelegate {
    static let shared = XboxPlayHistoryService()

    private var webView: WKWebView?
    private var completion: (([TrackedGame]) -> Void)?
    private var pollTask: Task<Void, Never>?
    private var isRunning = false
    private var lastFetch: Date = .distantPast

    /// Minimum gap between network scrapes.
    private let minInterval: TimeInterval = 90

    /// Scrape xbox.com/play for recently played titles and deliver TrackedGames.
    func refreshIfNeeded(force: Bool = false, completion: (([TrackedGame]) -> Void)? = nil) {
        if isRunning {
            completion?([])
            return
        }
        if !force, Date().timeIntervalSince(lastFetch) < minInterval {
            completion?([])
            return
        }

        isRunning = true
        self.completion = completion
        lastFetch = Date()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.processPool = SignInWebViewRepresentable.processPool
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        view.isHidden = true
        view.navigationDelegate = self
        view.customUserAgent = MicrosoftAuth.safariUserAgent
        self.webView = view

        view.load(URLRequest(url: MicrosoftAuth.playURL))

        // Hard stop so a hung page never leaves the service stuck.
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            guard !Task.isCancelled else { return }
            self.finish(with: [])
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give the SPA a moment to render Jump back in / Recently played.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            self?.extract(from: webView, attempt: 0)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: [])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: [])
    }

    private func extract(from webView: WKWebView, attempt: Int) {
        webView.evaluateJavaScript(Self.extractJS) { [weak self] result, _ in
            guard let self else { return }
            let games = Self.parse(result)
            if !games.isEmpty || attempt >= 4 {
                self.finish(with: games)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.extract(from: webView, attempt: attempt + 1)
            }
        }
    }

    private func finish(with games: [TrackedGame]) {
        pollTask?.cancel()
        pollTask = nil
        let done = completion
        completion = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        isRunning = false
        done?(games)
    }

    /// Collect product IDs + titles from xbox.com/play DOM (recent rails, cards, links).
    private static let extractJS = """
    (function() {
        function cleanTitle(t) {
            t = (t || '').replace(/\\s+/g, ' ').trim();
            if (!t) return '';
            t = t.split('\\n')[0].trim();
            if (t.length > 80) t = t.slice(0, 80);
            return t;
        }
        function parseHref(href) {
            if (!href) return null;
            try {
                var m = href.match(/\\/play\\/(?:games|launch)\\/([^\\/?#]+)\\/([A-Za-z0-9]{8,})/i);
                if (m) return { slug: m[1], id: m[2].toUpperCase() };
                m = href.match(/\\/play\\/launch\\/([A-Za-z0-9]{8,})/i);
                if (m) return { slug: m[1].toLowerCase(), id: m[1].toUpperCase() };
            } catch (e) {}
            return null;
        }
        var seen = {};
        var out = [];
        function push(item, title) {
            if (!item || !item.id || seen[item.id]) return;
            seen[item.id] = true;
            out.push({ id: item.id, slug: item.slug || item.id.toLowerCase(), title: cleanTitle(title) || item.slug || item.id });
        }

        // Prefer sections that look like recently played / jump back in.
        var sections = [];
        try {
            var all = document.querySelectorAll('section, [class*="recent"], [class*="Recent"], [class*="mru"], [class*="jump"], [data-testid]');
            for (var i = 0; i < all.length; i++) {
                var el = all[i];
                var label = ((el.getAttribute('aria-label') || '') + ' ' + (el.innerText || '')).toLowerCase();
                if (label.indexOf('recent') !== -1 || label.indexOf('jump back') !== -1 || label.indexOf('continue') !== -1 || label.indexOf('played') !== -1) {
                    sections.push(el);
                }
            }
        } catch (e) {}

        function scan(root, limit) {
            if (!root) return;
            var links = root.querySelectorAll('a[href*="/play/"]');
            for (var i = 0; i < links.length && out.length < limit; i++) {
                var a = links[i];
                var parsed = parseHref(a.getAttribute('href') || a.href || '');
                if (!parsed) continue;
                var title = cleanTitle(a.getAttribute('aria-label') || a.innerText || '');
                push(parsed, title);
            }
        }

        for (var s = 0; s < sections.length; s++) {
            scan(sections[s], 24);
        }
        // Fallback: whole page, but cap so featured carousels do not dominate.
        if (out.length < 4) {
            scan(document.body, 16);
        }

        // Also pull product IDs embedded in JSON blobs on the page.
        try {
            var html = document.documentElement.innerHTML || '';
            var re = /"productId"\\s*:\\s*"([A-Za-z0-9]{10,})"/g;
            var m;
            while ((m = re.exec(html)) && out.length < 24) {
                push({ id: m[1].toUpperCase(), slug: m[1].toLowerCase() }, '');
            }
        } catch (e) {}

        return JSON.stringify(out.slice(0, 24));
    })();
    """

    private static func parse(_ result: Any?) -> [TrackedGame] {
        guard let raw = result as? String,
              let data = raw.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var games: [TrackedGame] = []
        var seen = Set<String>()
        let now = Date()
        for (index, row) in rows.enumerated() {
            guard let id = (row["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  seen.insert(id.uppercased()).inserted else { continue }
            let slug = (row["slug"] as? String) ?? id.lowercased()
            var title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty || title.lowercased() == slug.lowercased() {
                title = GameCatalog.game(id: id)?.title
                    ?? GameURLParser.displayTitle(fromPageTitle: nil, slug: slug, productId: id)
            }
            // Stagger lastSeen so order is preserved (most recent first).
            let seenAt = now.addingTimeInterval(TimeInterval(-index))
            games.append(TrackedGame(id: id, slug: slug, title: title, lastSeen: seenAt, isFavorite: false))
        }
        return games
    }
}

extension SessionStore {
    /// Merge Xbox account recently-played into native recents (Xbox order wins on ties).
    func mergeXboxPlayHistory(_ incoming: [TrackedGame]) {
        guard !incoming.isEmpty else { return }
        var byId: [String: TrackedGame] = [:]
        for game in recents {
            byId[game.id.uppercased()] = game
        }
        var merged: [TrackedGame] = []
        var seen = Set<String>()
        for var xbox in incoming {
            let key = xbox.id.uppercased()
            if let local = byId[key] {
                xbox.isFavorite = local.isFavorite || isFavorite(xbox.id)
                if local.title.count > xbox.title.count { xbox.title = local.title }
            } else {
                xbox.isFavorite = isFavorite(xbox.id)
            }
            if seen.insert(key).inserted {
                merged.append(xbox)
            }
        }
        for local in recents {
            let key = local.id.uppercased()
            if seen.insert(key).inserted {
                merged.append(local)
            }
        }
        if merged.count > 24 { merged = Array(merged.prefix(24)) }
        recents = merged
        if let data = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(data, forKey: "GameStream.recents.v1")
        }
        ArtworkStore.shared.prefetch(merged.map(\.id))
        objectWillChange.send()
    }

    func refreshXboxPlayHistory(force: Bool = false) {
        guard isSignedIn else { return }
        XboxPlayHistoryService.shared.refreshIfNeeded(force: force) { [weak self] games in
            Task { @MainActor in
                self?.mergeXboxPlayHistory(games)
            }
        }
    }
}
