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

    /// Shared with XboxCloudWebView so Microsoft login cookies survive into Library.
    private static let sharedProcessPool = WKProcessPool()

    static var processPool: WKProcessPool { sharedProcessPool }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.processPool = Self.sharedProcessPool

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
