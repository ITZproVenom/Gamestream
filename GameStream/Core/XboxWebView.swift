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

        /// Runs a snippet inside the live player page.
        ///
        /// The native HUD needs to press controls that belong to the site, and
        /// this is the only handle on that webview once it is on screen.
        func run(_ javaScript: String) {
            guard let view = streamView else {
                // Silence here is indistinguishable from a button that did
                // nothing, so say so.
                AppLog.shared.warn("stream", "no player page is attached; the command was dropped")
                return
            }
            view.evaluateJavaScript(javaScript) { result, error in
                if let error {
                    AppLog.shared.warn("stream", "command failed: \(error.localizedDescription)")
                } else if let text = result as? String, !text.isEmpty {
                    AppLog.shared.debug("stream", text)
                }
            }
        }

        /// Evaluates a snippet and hands back whatever it returned.
        func evaluate(_ javaScript: String, then handler: @escaping (String) -> Void) {
            guard let view = streamView else { return }
            view.evaluateJavaScript(javaScript) { result, _ in
                handler((result as? String) ?? "")
            }
        }

        /// Runs an async snippet and waits for the promise it returns.
        ///
        /// `callAsyncJavaScript` is the only way to await a promise from
        /// native code; `evaluateJavaScript` hands back the promise object
        /// itself, which is useless here.
        func evaluateAsync(_ body: String) async -> Any? {
            guard let view = streamView else { return nil }
            return try? await view.callAsyncJavaScript(body,
                                                       arguments: [:],
                                                       in: nil,
                                                       contentWorld: .page)
        }

        func release() {
            guard let view = streamView else { return }
            streamView = nil
            view.stopLoading()
            view.navigationDelegate = nil
            view.uiDelegate = nil
            // Navigating away tears down the page's WebRTC session; simply
            // dropping the reference does not, and the audio can outlive it.
            view.loadHTMLString("", baseURL: nil)
            let controller = view.configuration.userContentController
            controller.removeAllUserScripts()
            controller.removeScriptMessageHandler(forName: "gamestream")
            view.removeFromSuperview()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(role: role)
    }

    func makeUIView(context: Context) -> WKWebView {
        if role == .stream, let existing = Registry.shared.streamView {
            existing.navigationDelegate = context.coordinator
            existing.uiDelegate = context.coordinator
            context.coordinator.attach(to: existing)
            // Adopt the current request state, otherwise the first update
            // after re-presenting looks like a change and reloads the page
            // that is already playing.
            context.coordinator.loadedURL = existing.url ?? url
            context.coordinator.reloadToken = reloadToken
            if existing.url == nil { existing.load(URLRequest(url: url)) }
            return existing
        }

        let configuration = XboxAuth.makeConfiguration()
        install(scripts: context.coordinator, into: configuration.userContentController)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = XboxAuth.userAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = role != .stream
        webView.isOpaque = role != .stream
        webView.backgroundColor = role == .stream ? .black : nil
        webView.scrollView.backgroundColor = role == .stream ? .black : nil

        if role == .stream {
            webView.scrollView.bounces = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            Registry.shared.streamView = webView

            // A SwiftUI tap gesture on the view behind this one never fires:
            // the web view consumes the touch, and with touch controls drawn
            // over the video it consumes all of them. That is why the overlay
            // vanished after a few seconds and could not be brought back —
            // every button on it was unreachable for the rest of the session.
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleOverlayTap))
            tap.numberOfTapsRequired = 2
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = context.coordinator
            webView.addGestureRecognizer(tap)
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
        let settings = AppSettings.shared
        controller.addUserScript(WKUserScript(
            source: ControllerRumble.shared.pageConfigurationJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: RumbleBridge.javaScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        // GameStream's own enhancement layer wraps RTCPeerConnection, so like
        // the rumble bridge it has to be in place before the page builds one.
        controller.addUserScript(WKUserScript(
            source: StreamEnhancer.script(settings.enhancerConfiguration()),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true))
        // Auto-start is a preference, so the script that presses the site's
        // Play button is only installed when it is on. Injecting it and
        // ignoring the setting is how a switch ends up doing nothing.
        var sources = [WebScripts.streamStateJS, WebScripts.streamChromeJS,
                       WebScripts.streamStatsJS, WebScripts.streamCommandsJS,
                       WebScripts.captureJS]
        if settings.autoStart { sources.append(WebScripts.autoStartJS) }
        for source in sources {
            controller.addUserScript(WKUserScript(source: source,
                                                  injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true))
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
                             UIGestureRecognizerDelegate {

        /// Two fingers-free taps toggle the app's overlay. It runs alongside
        /// the page's own handling rather than instead of it, so touch
        /// controls keep working.
        @objc func handleOverlayTap() {
            StreamCoordinator.shared.requestOverlay()
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

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
            case "stats":
                StreamCoordinator.shared.statsUpdated(StreamStats(payload: body))
            case "command":
                let detail = body["detail"] as? String ?? ""
                log.info("stream", "\(body["command"] as? String ?? "command"): \(detail)")
                StreamCoordinator.shared.show(notice: detail)
            case "enhance":
                let codecs = body["codecs"] as? String ?? ""
                let notes = body["notes"] as? String ?? ""
                StreamCoordinator.shared.enhancementReported(codecs: codecs, notes: notes)
            case "rumble":
                RumbleBridge.handle(payload: body)
            case "rumbleCaps":
                RumbleBridge.handleCapabilities(payload: body)
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

        /// WebKit runs pages in a separate process, and that process can be
        /// killed under memory pressure. When it is, the view goes blank and
        /// nothing else reports anything: the stream simply stops with no
        /// error and no end. This is the only notice the app gets.
        @MainActor
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            AppLog.shared.warn("web", "\(role) page process was terminated")
            guard role == .stream else {
                webView.reload()
                return
            }
            StreamCoordinator.shared.streamFailed(
                message: "The player ran out of memory and was shut down by iOS."
            )
        }

        // MARK: Popups
        //
        // Microsoft's sign-in can open a new window. A webview with no
        // WKUIDelegate silently discards that request, so the button appears
        // to do nothing. Returning nil and loading the request in the current
        // webview keeps the flow in one place, where the shared data store and
        // the session both already live.
        @MainActor
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, navigationAction.targetFrame == nil {
                AppLog.shared.debug("web", "following popup to \(url.host ?? "a new window")")
                webView.load(navigationAction.request)
            }
            return nil
        }

        // The site uses these for consent and error prompts; without a
        // delegate they never appear and the page waits forever.
        @MainActor
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo) async {
            AppLog.shared.info("web", "page alert: \(message)")
        }

        @MainActor
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo) async -> Bool {
            AppLog.shared.info("web", "page confirm: \(message)")
            return true
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
