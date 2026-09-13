import SwiftUI
import WebKit

struct StreamPlayerView: View {
    var body: some View {
        XboxCloudWebView()
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct XboxCloudWebView: UIViewRepresentable {
    let url: URL

    init(url: URL = URL(string: "https://www.xbox.com/play")!) {
        self.url = url
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(
            frame: .zero,
            configuration: config
        )

        webView.navigationDelegate = context.coordinator

        webView.load(
            URLRequest(url: url)
        )

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            NotificationCenter.default.post(
                name: .webViewLoadingChanged,
                object: true
            )
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            NotificationCenter.default.post(
                name: .webViewLoadingChanged,
                object: false
            )
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            NotificationCenter.default.post(
                name: .webViewLoadingChanged,
                object: false
            )
        }
    }
}

extension Notification.Name {
    static let webViewLoadingChanged =
        Notification.Name("webViewLoadingChanged")
}