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

    /// Current URL loaded in the Xbox Cloud webview.
    @Published var webURL: URL = URL(string: "https://www.xbox.com/play")!

    /// Used by RootView to switch to Library when search is triggered.
    @Published var requestedTab: RootView.Tab? = nil

    /// True while an actual game stream is running (hides native chrome).
    @Published var isStreaming: Bool = false

    private enum Keys {
        static let signedIn = "GameStream.isSignedIn"
        static let accountLabel = "GameStream.accountLabel"
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

        // Clear Xbox / Microsoft website data so the web session is also ended
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
    }

    func reloadCurrent() {
        let current = webURL
        webURL = current
    }

    func updateFromWebURL(_ url: URL) {
        webURL = url
        let path = url.path.lowercased()
        let streaming = path.contains("/launch") || path.contains("/play/game")
        if isStreaming != streaming {
            isStreaming = streaming
        }
    }
}
