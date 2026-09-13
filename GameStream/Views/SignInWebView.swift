import SwiftUI
import WebKit

/// Sign-in surface — same Xbox login page used by the official app/website.
struct SignInWebView: View {
    var body: some View {
        WebViewRepresentable(url: URL(string: "https://www.xbox.com/play")!)
            .ignoresSafeArea()
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
