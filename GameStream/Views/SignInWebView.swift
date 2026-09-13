import SwiftUI
import WebKit

/// Sign-in surface — Microsoft's real hosted login, shared cookie store with Library webview.
struct SignInWebView: View {
    var body: some View {
        SignInWebViewRepresentable(url: MicrosoftAuth.loginURL)
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
        private var sawMicrosoftLoginHost = false
        private var completing = false

        init(session: SessionStore) {
            self.session = session
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            note(url: webView.url)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            note(url: webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            note(url: webView.url)
            considerComplete(webView: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            note(url: navigationAction.request.url ?? webView.url)
            decisionHandler(.allow)
        }

        private func note(url: URL?) {
            guard let raw = url?.absoluteString else { return }
            if MicrosoftAuth.isLoginHost(raw) {
                sawMicrosoftLoginHost = true
            }
        }

        private func considerComplete(webView: WKWebView) {
            guard !completing else { return }
            guard let href = webView.url?.absoluteString else { return }
            // Landing on /play without visiting Microsoft login is not authentication.
            guard sawMicrosoftLoginHost, MicrosoftAuth.isXboxDestination(href) else { return }
            completing = true
            MicrosoftAuth.fetchAuthCookies { cookies in
                let ok = MicrosoftAuth.cookiesIndicateMicrosoftAuth(cookies)
                Task { @MainActor in
                    if ok {
                        self.session?.markSignedInAfterMicrosoftAuth()
                    } else {
                        self.completing = false
                    }
                }
            }
        }
    }
}
