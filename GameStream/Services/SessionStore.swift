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

    func markSignedIn(as label: String = "Xbox Account") {
        self.accountLabel = label
        self.isSignedIn = true
    }

    func signOut() {
        isSignedIn = false
        accountLabel = nil
        webURL = URL(string: "https://www.xbox.com/play")!
    }

    /// Open a search query inside the Library webview and switch to it.
    func openSearch(query: String) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.xbox.com/play/search?q=\(encoded)") else { return }

        webURL = url
        requestedTab = .library
    }

    func openHome() {
        webURL = URL(string: "https://www.xbox.com/play")!
    }

    func reloadCurrent() {
        // Trigger a reload by re-assigning the same URL (webview observes changes).
        let current = webURL
        webURL = current
    }
}
