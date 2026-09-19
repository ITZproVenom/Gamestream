import SwiftUI
import WebKit

/// Sign-in surface — Microsoft's real hosted login, shared cookie store with the
/// streaming WebView. Signed-in is only marked after an actual xbox.com session
/// cookie appears in the store; login.live.com cookies alone are not enough.
struct SignInWebView: View {
    var body: some View {
        SignInWebViewRepresentable(url: MicrosoftAuth.loginURL)
            .ignoresSafeArea()
    }
}

struct SignInWebViewRepresentable: UIViewRepresentable {
    let url: URL
    @EnvironmentObject var session: SessionStore

    /// Shared with XboxCloudWebView so Microsoft login cookies survive into the stream.
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
        // Critical: default WKWebView UA is often blocked by Akamai on xbox.com.
        webView.customUserAgent = MicrosoftAuth.safariUserAgent
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        private weak var session: SessionStore?
        private var sawMicrosoftLoginHost = false
        private var completing = false
        private var recoveredFromAkamai = false

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
            recoverIfAkamaiDenied(webView: webView)
            considerComplete(webView: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            note(url: navigationAction.request.url ?? webView.url)

            if let requestURL = navigationAction.request.url,
               let https = MicrosoftAuth.httpsXboxURL(from: requestURL) {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: https))
                return
            }

            decisionHandler(.allow)
        }

        private func note(url: URL?) {
            guard let raw = url?.absoluteString else { return }
            if MicrosoftAuth.isLoginHost(raw) {
                sawMicrosoftLoginHost = true
            }
        }

        /// If Akamai served Access Denied for the post-login landing, try once more
        /// against the known-good HTTPS en-US play URL with the Safari UA already set.
        private func recoverIfAkamaiDenied(webView: WKWebView) {
            guard !recoveredFromAkamai else { return }
            guard let href = webView.url?.absoluteString else { return }
            let deniedByURL = MicrosoftAuth.isAkamaiDenied(href)

            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
                let body = (result as? String)?.lowercased() ?? ""
                let deniedByBody = body.contains("access denied") || body.contains("edgesuite")
                guard deniedByURL || deniedByBody else { return }
                self.recoveredFromAkamai = true
                DispatchQueue.main.async {
                    webView.load(URLRequest(url: MicrosoftAuth.playURL))
                }
            }
        }

        private func considerComplete(webView: WKWebView) {
            guard !completing else { return }
            guard let href = webView.url?.absoluteString else { return }
            // Landing on /play without visiting Microsoft login is not authentication.
            guard sawMicrosoftLoginHost, MicrosoftAuth.isXboxDestination(href) else { return }
            completing = true
            pollForXboxSession(attempt: 0)
        }

        /// xbox.com sets its session cookies (RPSTAuth/XBL3) when it processes the
        /// login redirect, which can lag the page-load finish event. Poll the shared
        /// cookie store so we only mark signed-in when the session actually exists.
        private func pollForXboxSession(attempt: Int) {
            MicrosoftAuth.fetchAuthCookies { cookies in
                if MicrosoftAuth.cookiesIndicateXboxSession(cookies) {
                    Task { @MainActor in
                        self.session?.markSignedInAfterMicrosoftAuth()
                    }
                    return
                }
                guard attempt < 8 else {
                    self.completing = false
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.pollForXboxSession(attempt: attempt + 1)
                }
            }
        }
    }
}
