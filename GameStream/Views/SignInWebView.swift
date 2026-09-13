import SwiftUI
import WebKit

/// Sign-in surface — same Xbox login page, shared cookie store with Library webview.
struct SignInWebView: View {
    var body: some View {
        SignInWebViewRepresentable(url: URL(string: "https://www.xbox.com/play")!)
            .ignoresSafeArea()
    }
}

struct SignInWebViewRepresentable: UIViewRepresentable {
    let url: URL
    @EnvironmentObject var session: SessionStore

    /// Shared with XboxCloudWebView so Microsoft login cookies survive into Library.
    private static let sharedProcessPool = WKProcessPool()

    static var processPool: WKProcessPool { sharedProcessPool }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.processPool = Self.sharedProcessPool
        config.allowsInlineMediaPlayback = true

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        private weak var session: SessionStore?

        init(session: SessionStore) {
            self.session = session
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let href = webView.url?.absoluteString.lowercased() else { return }
            // After Microsoft login, Xbox Cloud lands back on /play (not login.live.com).
            let onXboxPlay = href.contains("xbox.com") && href.contains("/play")
            let onLoginHost = href.contains("login.live.com") || href.contains("login.microsoftonline.com")
            if onXboxPlay && !onLoginHost {
                Task { @MainActor in
                    session?.markSignedIn()
                }
            }
        }
    }
}
