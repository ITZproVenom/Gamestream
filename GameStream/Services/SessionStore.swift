import Foundation
import Combine
import WebKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var isSignedIn: Bool {
        didSet { UserDefaults.standard.set(isSignedIn, forKey: Keys.signedIn) }
    }

    @Published var accountLabel: String? {
        didSet { UserDefaults.standard.set(accountLabel, forKey: Keys.accountLabel) }
    }

    /// App-driven destination only. Do not write this from in-page navigation
    /// or the webview will hard-reload on every SPA route change.
    @Published var webURL: URL = URL(string: "https://www.xbox.com/play")!

    @Published var requestedTab: RootView.Tab? = nil
    @Published var isStreaming: Bool = false

    /// JS snippets the webview should evaluate on next opportunity.
    @Published var pendingJavaScript: String?

    /// Bumped to force webview re-injection / reload of Better xCloud script.
    @Published var betterXCloudRefreshToken: Int = 0

    /// Bumped to force a hard reload even when URL is unchanged.
    @Published var reloadNonce: Int = 0

    private enum Keys {
        static let signedIn = "GameStream.isSignedIn"
        static let accountLabel = "GameStream.accountLabel"
        static let streamResolution = "GameStream.streamResolution"
        static let serverRegion = "GameStream.serverRegion"
    }

    init() {
        self.isSignedIn = UserDefaults.standard.bool(forKey: Keys.signedIn)
        self.accountLabel = UserDefaults.standard.string(forKey: Keys.accountLabel)
    }

    func markSignedIn(as label: String = "Xbox Account") {
        self.accountLabel = label
        self.isSignedIn = true
    }

    func signOut() {
        isSignedIn = false
        accountLabel = nil
        isStreaming = false
        webURL = URL(string: "https://www.xbox.com/play")!

        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let xboxRecords = records.filter {
                let name = $0.displayName.lowercased()
                return name.contains("xbox") || name.contains("microsoft") || name.contains("live") || name.contains("bing")
            }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: xboxRecords) {}
        }
    }

    func openSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")

        // Stay on /play so we do not bounce through a non-existent /play/search route.
        webURL = URL(string: "https://www.xbox.com/play")!
        isStreaming = false
        pendingJavaScript = """
        (function() {
            var q = '\(escaped)';
            function findInput() {
                return document.querySelector('input[type="search"], input[placeholder*="Search" i], input[aria-label*="Search" i], input[name="q"]');
            }
            var input = findInput();
            if (!input) {
                var btn = document.querySelector('button[aria-label*="Search" i], [role="search"] button, a[href*="search"]');
                if (btn) { try { btn.click(); } catch (e) {} }
            }
            setTimeout(function() {
                input = findInput();
                if (input) {
                    input.focus();
                    try {
                        var proto = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
                        if (proto && proto.set) proto.set.call(input, q); else input.value = q;
                    } catch (e) { input.value = q; }
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.dispatchEvent(new Event('change', { bubbles: true }));
                    var form = input.closest('form');
                    if (form) {
                        form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
                    } else {
                        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', keyCode: 13, which: 13, bubbles: true }));
                    }
                } else {
                    location.href = 'https://www.xbox.com/play?search=' + encodeURIComponent(q);
                }
            }, 280);
        })();
        """
        requestedTab = .library
    }

    func openHome() {
        webURL = URL(string: "https://www.xbox.com/play")!
        isStreaming = false
        requestedTab = .library
    }

    func reloadCurrent() {
        reloadNonce += 1
        pendingJavaScript = "try { location.reload(); } catch (e) {}"
    }

    /// Called from the webview bridge. Updates streaming state only — never webURL.
    func updateFromWebURL(_ url: URL) {
        let streaming = Self.isStreamingURL(url.absoluteString)
        if isStreaming != streaming {
            isStreaming = streaming
        }
    }

    /// Catalog pages like /play/games/... are not an active stream.
    static func isStreamingURL(_ raw: String) -> Bool {
        let full = raw.lowercased()
        if full.contains("/play/games") { return false }
        return full.contains("/play/launch") ||
            full.contains("/launch/") ||
            full.contains("/launch?") ||
            full.contains("/stream/") ||
            full.contains("/streaming")
    }

    // MARK: - Better xCloud preference bridging

    func applyBetterXCloudPref(_ prefKey: String, value: String) {
        let escapedKey = prefKey.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let escapedValue = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let js = """
        (function() {
            try {
                var storageKey = 'BetterXcloud';
                var data = {};
                try { data = JSON.parse(localStorage.getItem(storageKey) || '{}') || {}; } catch (e) { data = {}; }
                data['\(escapedKey)'] = '\(escapedValue)';
                localStorage.setItem(storageKey, JSON.stringify(data));
                try { localStorage.setItem('BetterXcloud.\(escapedKey)', '\(escapedValue)'); } catch (e) {}
                setTimeout(function() { location.reload(); }, 120);
            } catch (e) {}
        })();
        """

        pendingJavaScript = js
        requestedTab = .library
        isStreaming = false
        if !webURL.absoluteString.contains("xbox.com/play") {
            webURL = URL(string: "https://www.xbox.com/play")!
        }
    }

    func applyStreamResolution(_ resolution: String) {
        UserDefaults.standard.set(resolution, forKey: Keys.streamResolution)
        let mapped: String
        switch resolution {
        case "720p": mapped = "720p"
        case "1080p": mapped = "1080p"
        case "1080p HQ": mapped = "1080p-hq"
        default: mapped = "auto"
        }
        applyBetterXCloudPref("stream.video.resolution", value: mapped)
    }

    func applyServerRegion(_ region: String) {
        UserDefaults.standard.set(region, forKey: Keys.serverRegion)
        let mapped: String
        switch region {
        case "North America": mapped = "us"
        case "Europe": mapped = "eu"
        case "Asia": mapped = "jp"
        case "Australia": mapped = "au"
        default: mapped = ""
        }
        applyBetterXCloudPref("server.region", value: mapped)
    }

    func refreshBetterXCloudScript() {
        UserDefaults.standard.removeObject(forKey: "BetterXCloud.Script.v2")
        UserDefaults.standard.removeObject(forKey: "BetterXCloud.Script.Date.v2")
        betterXCloudRefreshToken += 1
        pendingJavaScript = "try { location.reload(); } catch (e) {}"
        requestedTab = .library
    }

    func clearWebData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            Task { @MainActor in
                self?.webURL = URL(string: "https://www.xbox.com/play")!
                self?.isStreaming = false
                self?.pendingJavaScript = "try { location.reload(); } catch (e) {}"
                self?.requestedTab = .library
            }
        }
    }

    static var storedResolution: String {
        UserDefaults.standard.string(forKey: Keys.streamResolution) ?? "Auto"
    }

    static var storedRegion: String {
        UserDefaults.standard.string(forKey: Keys.serverRegion) ?? "Auto"
    }
}
