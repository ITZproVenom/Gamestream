import SwiftUI
import WebKit

struct StreamPlayerView: View {
    var body: some View {
        XboxCloudWebView(url: .constant(URL(string: "https://www.xbox.com/play")!))
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct XboxCloudWebView: UIViewRepresentable {
    @Binding var url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true

        // Prefer desktop-like experience for Xbox Cloud
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black

        // Initial load
        webView.load(URLRequest(url: url))
        context.coordinator.lastLoadedURL = url

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Only reload when the URL actually changes
        if context.coordinator.lastLoadedURL != url {
            context.coordinator.lastLoadedURL = url
            uiView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedURL: URL?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            NotificationCenter.default.post(name: .webViewDidFail, object: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NotificationCenter.default.post(name: .webViewLoadingChanged, object: false)
            NotificationCenter.default.post(name: .webViewDidFail, object: error.localizedDescription)
        }
    }
}

extension Notification.Name {
    static let webViewLoadingChanged = Notification.Name("webViewLoadingChanged")
    static let webViewDidFail = Notification.Name("webViewDidFail")
}
