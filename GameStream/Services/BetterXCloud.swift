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
    private static let maxAge: TimeInterval = 86_400

    /// Read synchronously when building a webview configuration, which happens
    /// on the main actor and cannot await.
    nonisolated var cachedScript: String? {
        let value = UserDefaults.standard.string(forKey: Self.scriptKey)
        return (value?.isEmpty == false) ? value : nil
    }

    nonisolated var lastFetched: Date? {
        UserDefaults.standard.object(forKey: Self.fetchedKey) as? Date
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
            UserDefaults.standard.set(script, forKey: Self.scriptKey)
            UserDefaults.standard.set(Date(), forKey: Self.fetchedKey)
            await log(.info, "Better xCloud updated (\(script.count) characters)")
            return true
        } catch {
            await log(.warn, "could not fetch Better xCloud: \(error.localizedDescription)")
            return false
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.scriptKey)
        UserDefaults.standard.removeObject(forKey: Self.fetchedKey)
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
