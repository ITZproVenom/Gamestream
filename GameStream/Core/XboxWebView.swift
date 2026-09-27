import SwiftUI
import WebKit

/// The one webview type in the app, specialised by role.
///
/// Every role shares `WKWebsiteDataStore.default()`, which is what actually
/// carries the session between signing in, browsing and streaming. What
/// differs is the JavaScript each role injects, and that separation is
/// deliberate: the sign-in page gets nothing at all, so no GameStream script
/// can interfere with Microsoft's login, and the browser no longer inherits
/// the player's chrome-hiding CSS.
struct XboxWebView: UIViewRepresentable {
    enum Role: Equatable {
        /// Microsoft's hosted login. Nothing is injected here.
        case signIn
        /// Plain xbox.com browsing.
        case browse
        /// A game launch page, with the player scripts and rumble bridge.
        case stream
    }

    let role: Role
    let url: URL
    /// Bumping this reloads the page without recreating the webview.
    var reloadToken: Int = 0

    @MainActor
    final class Registry {
        static let shared = Registry()
        /// The player webview outlives any single presentation so dismissing a
        /// sheet cannot tear down a live stream and force a reconnect.
        var streamView: WKWebView?
        private init() {}
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(role: role)
    }

    func makeUIView(context: Context) -> WKWebView {
        if role == .stream, let existing = Registry.shared.streamView {
            existing.navigationDelegate = context.coordinator
            context.coordinator.attach(to: existing)
            if existing.url == nil { existing.load(URLRequest(url: url)) }
            return existing
        }

        let configuration = XboxAuth.makeConfiguration()
        install(scripts: context.coordinator, into: configuration.userContentController)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = XboxAuth.userAgent
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = role != .stream
        webView.isOpaque = role != .stream
        webView.backgroundColor = role == .stream ? .black : nil
        webView.scrollView.backgroundColor = role == .stream ? .black : nil

        if role == .stream {
            webView.scrollView.bounces = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            Registry.shared.streamView = webView
        }

        context.coordinator.attach(to: webView)
        webView.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        context.coordinator.reloadToken = reloadToken
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.reload()
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // The player webview is intentionally kept alive between presentations.
        if coordinator.role != .stream {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
    }

    @MainActor
    private func install(scripts coordinator: Coordinator, into controller: WKUserContentController) {
        controller.add(coordinator, name: "gamestream")

        // Every role reports navigation so the app can follow SPA routing.
        controller.addUserScript(WKUserScript(source: WebScripts.navigationBridgeJS,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))

        guard role == .stream else { return }

        // The rumble bridge must wrap createDataChannel before the page opens
        // its WebRTC session, so it has to run at document start.
        controller.addUserScript(WKUserScript(source: RumbleBridge.javaScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: WebScripts.betterXCloudPrefsJS(AppSettings.shared.betterXCloudPreferences()),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        if let script = BetterXCloud.shared.cachedScript {
            controller.addUserScript(WKUserScript(source: script,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
        }
        for source in [WebScripts.streamStateJS, WebScripts.streamChromeJS, WebScripts.autoStartJS] {
            controller.addUserScript(WKUserScript(source: source,
                                                  injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true))
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let role: Role
        var loadedURL: URL?
        var reloadToken = 0
        private weak var webView: WKWebView?
        private let log = AppLog.shared

        init(role: Role) {
            self.role = role
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
        }

        // MARK: Messages from the page

        // WKScriptMessage is main-actor state, so read it there rather than
        // reaching into it from a nonisolated context.
        @MainActor
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            handle(type: type, body: body)
        }

        private func handle(type: String, body: [String: Any]) {
            switch type {
            case "nav":
                let kind = body["kind"] as? String ?? "other"
                StreamCoordinator.shared.pageChanged(kind: kind,
                                                     href: body["href"] as? String ?? "",
                                                     role: role)
            case "streamPlaying":
                let width = body["width"] as? Int ?? 0
                let height = body["height"] as? Int ?? 0
                StreamCoordinator.shared.streamStarted(width: width, height: height)
            case "streamError":
                StreamCoordinator.shared.streamFailed(message: body["message"] as? String ?? "")
            case "autoStart":
                log.info("stream", "pressed the site's \"\(body["label"] as? String ?? "")\" button")
            case "rumble":
                RumbleBridge.handle(payload: body)
            default:
                break
            }
        }

        // MARK: Navigation

        @MainActor
        func webView(_ webView: WKWebView,
                     didStartProvisionalNavigation navigation: WKNavigation!) {
            if role == .stream { StreamCoordinator.shared.loadingChanged(true) }
        }

        @MainActor
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let href = webView.url?.absoluteString ?? ""
            if role == .stream { StreamCoordinator.shared.loadingChanged(false) }
            if href.lowercased().contains("/auth/msa") {
                XboxAuth.shared.noteAuthRedirect()
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                                 withError error: Error) {
            report(error)
        }

        nonisolated func webView(_ webView: WKWebView,
                                 didFailProvisionalNavigation navigation: WKNavigation!,
                                 withError error: Error) {
            report(error)
        }

        private nonisolated func report(_ error: Error) {
            let code = (error as NSError).code
            let detail = error.localizedDescription
            Task { @MainActor in
                // -999 is "a newer navigation replaced this one", which is
                // normal on a single-page app and must not look like a failure.
                guard code != NSURLErrorCancelled else { return }
                AppLog.shared.warn("web", "\(role) navigation failed: \(detail)")
                if role == .stream {
                    StreamCoordinator.shared.loadingChanged(false)
                    StreamCoordinator.shared.streamFailed(message: detail)
                }
            }
        }
    }
}
