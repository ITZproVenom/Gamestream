import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var accountLabel: String?

    /// Current URL loaded in the Xbox Cloud webview.
    @Published var webURL: URL = URL(string: "https://www.xbox.com/play")!

    /// Used by RootView to switch to Library when search is triggered.
    @Published var requestedTab: RootView.Tab? = nil

    /// True while an actual game stream is running (hides native chrome).
    @Published var isStreaming: Bool = false

    func markSignedIn(as label: String = "Xbox Account") {
        self.accountLabel = label
        self.isSignedIn = true
    }

    func signOut() {
        isSignedIn = false
        accountLabel = nil
        isStreaming = false
        webURL = URL(string: "https://www.xbox.com/play")!
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

    /// Called by the webview when the page URL changes.
    func updateFromWebURL(_ url: URL) {
        webURL = url
        let path = url.path.lowercased()
        // Typical stream paths: /play/launch/..., /play/consoles/launch/...
        let streaming = path.contains("/launch") || path.contains("/play/game")
        if isStreaming != streaming {
            isStreaming = streaming
        }
    }
}
