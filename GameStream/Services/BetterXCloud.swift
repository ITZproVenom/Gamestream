import Foundation

/// Downloads and caches the Better xCloud userscript.
///
/// The script is only ever installed as a `WKUserScript` at document start.
/// 1.x also re-ran the whole script with `evaluateJavaScript` after every
/// navigation, so the page ended up with the script applied twice and two sets
/// of event handlers and menus.
actor BetterXCloud {
    static let shared = BetterXCloud()

    private static let sourceURL = URL(
        string: "https://github.com/redphx/better-xcloud/releases/latest/download/better-xcloud.user.js"
    )!
    private static let scriptKey = "betterXCloud.script"
    private static let fetchedKey = "betterXCloud.fetchedAt"
    private static let versionKey = "betterXCloud.version"
    private static let maxAge: TimeInterval = 86_400

    /// Everything Better xCloud keeps in the page's localStorage. A reinstall
    /// that leaves these behind is not a reinstall: its cached patch bundle
    /// and its settings outlive the script that wrote them, and a stale patch
    /// cache against a newer page is exactly how its buttons stop responding.
    static let storageKeys = [
        "BetterXcloud",
        "BetterXcloud.Stream",
        "BetterXcloud.Locale",
        "BetterXcloud.Locale.Translations",
        "BetterXcloud.UserAgent",
        "BetterXcloud.Patches.Cache",
        "BetterXcloud.Patches.Cache.Signature",
        "BetterXcloud.GhPages.CommitHash",
        "BetterXcloud.GhPages.CustomTouchLayouts",
        "BetterXcloud.GhPages.ForceNativeMkb",
        "BetterXcloud.GhPages.LocalCoOp"
    ]

    /// Clears that storage inside the page, including any key the script adds
    /// later that keeps to its own prefix.
    static let purgeJS: String = {
        let list = storageKeys.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        (function() {
            var removed = [];
            try {
                var known = [\(list)];
                for (var i = 0; i < known.length; i++) {
                    if (localStorage.getItem(known[i]) !== null) {
                        localStorage.removeItem(known[i]);
                        removed.push(known[i]);
                    }
                }
                for (var j = localStorage.length - 1; j >= 0; j--) {
                    var key = localStorage.key(j);
                    if (key && key.indexOf("BetterXcloud") === 0) {
                        localStorage.removeItem(key);
                        removed.push(key);
                    }
                }
            } catch (e) {}
            return removed.join(", ");
        })();
        """
    }()

    /// Read synchronously when building a webview configuration, which happens
    /// on the main actor and cannot await.
    nonisolated var cachedScript: String? {
        let value = UserDefaults.standard.string(forKey: Self.scriptKey)
        return (value?.isEmpty == false) ? value : nil
    }

    nonisolated var lastFetched: Date? {
        UserDefaults.standard.object(forKey: Self.fetchedKey) as? Date
    }

    /// The `@version` from the userscript header, so Settings can name the
    /// build rather than only the day it was downloaded.
    nonisolated var version: String? {
        UserDefaults.standard.string(forKey: Self.versionKey)
    }

    private var isFetching = false

    /// Fetch the script if it is missing or a day old.
    func refreshIfNeeded() async {
        let age = Date().timeIntervalSince(lastFetched ?? .distantPast)
        guard cachedScript == nil || age > Self.maxAge else { return }
        await refresh()
    }

    @discardableResult
    func refresh() async -> Bool {
        guard !isFetching else { return false }
        isFetching = true
        defer { isFetching = false }

        var request = URLRequest(url: Self.sourceURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                await log(.warn, "unexpected response fetching Better xCloud")
                return false
            }
            guard let raw = String(data: data, encoding: .utf8), raw.count > 1000 else {
                await log(.warn, "Better xCloud download was too small to use")
                return false
            }
            let script = Self.stripUserScriptHeader(raw)
            let version = Self.parseVersion(raw)
            UserDefaults.standard.set(script, forKey: Self.scriptKey)
            UserDefaults.standard.set(Date(), forKey: Self.fetchedKey)
            UserDefaults.standard.set(version, forKey: Self.versionKey)
            await log(.info, "Better xCloud \(version ?? "?") installed "
                      + "(\(script.count) characters)")
            return true
        } catch {
            await log(.warn, "could not fetch Better xCloud: \(error.localizedDescription)")
            return false
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.scriptKey)
        UserDefaults.standard.removeObject(forKey: Self.fetchedKey)
        UserDefaults.standard.removeObject(forKey: Self.versionKey)
    }

    /// A genuine reinstall: throw away the cached script, throw away what the
    /// script stored in the page, download it again, and let the next stream
    /// start from nothing. Refreshing alone left the old patch cache in place.
    @discardableResult
    func reinstall() async -> Bool {
        await log(.info, "reinstalling Better xCloud")
        await MainActor.run {
            XboxWebView.Registry.shared.purgeBetterXCloudStorage()
            XboxWebView.Registry.shared.release()
        }
        clear()
        let ok = await refresh()
        if !ok { await log(.warn, "reinstall could not download the script") }
        return ok
    }

    private static func parseVersion(_ source: String) -> String? {
        for line in source.components(separatedBy: "\n").prefix(40) {
            guard line.contains("@version") else { continue }
            let parts = line.split(separator: " ").filter { !$0.isEmpty }
            if let value = parts.last, value != "@version" { return String(value) }
        }
        return nil
    }

    /// The userscript metadata block is not valid JavaScript on its own.
    private static func stripUserScriptHeader(_ source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        guard lines.first?.contains("==UserScript==") == true,
              let end = lines.firstIndex(where: { $0.contains("==/UserScript==") }) else {
            return source
        }
        lines = Array(lines.suffix(from: end + 1))
        return lines.joined(separator: "\n")
    }

    private func log(_ level: AppLog.Level, _ message: String) async {
        await MainActor.run { AppLog.shared.record(level, "betterxcloud", message) }
    }
}
