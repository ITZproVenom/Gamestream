import SwiftUI
import WebKit

/// Streams via Xbox Cloud Gaming's own web client (cloud.xbox.com/play),
/// using your existing Xbox login — same approach a browser uses, just
/// wrapped in a native shell. No private API involved.
struct StreamPlayerView: View {
    let game: GameEntry

    var body: some View {
        XboxCloudWebView()
            .ignoresSafeArea()
    }
}

struct XboxCloudWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: URL(string: "https://www.xbox.com/play")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
