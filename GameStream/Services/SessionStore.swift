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
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.xbox.com/play/search?q=\(encoded)") else { return }
        webURL = url
        isStreaming = false
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
        let path = url.path.lowercased()
        let full = url.absoluteString.lowercased()
        let streaming =
            path.contains("/launch") ||
            path.contains("/play/game") ||
            path.contains("/play/launch") ||
            full.contains("/launch/") ||
            full.contains("streaming") ||
            full.contains("/stream")

        if isStreaming != streaming {
            isStreaming = streaming
        }
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
