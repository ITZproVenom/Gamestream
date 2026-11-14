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
        /// A Cloud Gaming search page whose rendered results are returned to the
        /// native Search UI.
        case searchResults
        /// A game launch page, with the player scripts and rumble bridge.
        case stream
    }

    let role: Role
    let url: URL
    /// Bumping this reloads the page without recreating the webview.
    var reloadToken: Int = 0
    /// Receives native models extracted from Xbox's rendered search results.
    var onSearchResults: ((URL, [Game], String, String) -> Void)? = nil

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

        /// Wipes what Better xCloud stored inside the page.
        ///
        /// A live page is cleaned immediately; the flag makes the next page
        /// clean itself before the script runs, which is the case that
        /// matters when nothing is streaming at the time.
        func purgeBetterXCloudStorage() {
            UserDefaults.standard.set(true, forKey: "betterXCloud.purgePending")
            guard let view = streamView else { return }
            view.evaluateJavaScript(BetterXCloud.purgeJS) { result, _ in
                let removed = (result as? String) ?? ""
                AppLog.shared.info("betterxcloud", removed.isEmpty
                                   ? "nothing stored in the page to clear"
                                   : "cleared from the page: \(removed)")
            }
        }

        /// Runs a snippet and hands back what it evaluated to.
        func evaluate(_ javaScript: String, completion: @escaping (String) -> Void) {
            guard let view = streamView else { return completion("") }
            view.evaluateJavaScript(javaScript) { result, _ in
                completion((result as? String) ?? "")
            }
        }

        /// Awaits an async snippet and hands back its resolved value.
        func evaluateAsync(_ javaScript: String) async -> Any? {
            guard let view = streamView else { return nil }
            return try? await view.callAsyncJavaScript(javaScript,
                                                       contentWorld: .page)
        }

        /// Ends the session for real.
        ///
        /// Because the player webview is deliberately kept alive between
        /// presentations, leaving the stream is the only point at which it can
        /// be stopped. Without this the page keeps running after exit, still
        /// holding the Xbox session open and still pulling video.
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
        Coordinator(role: role, onSearchResults: onSearchResults)
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
        // The stream player must look like a desktop PC browser: on an iOS
        // UA the site demands the home-screen PWA (navigator.standalone) and
        // bounces the launch to the store page. Every other role keeps the
        // mobile Safari UA.
        webView.customUserAgent = role == .stream ? XboxAuth.desktopUserAgent : XboxAuth.userAgent
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
            // The page needs to hear about the controller as it is used, so
            // the mirroring starts with the page and stops with it.
            GamepadBridge.shared.attach()

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
        context.coordinator.onSearchResults = onSearchResults
        let addressChanged = context.coordinator.loadedURL != url
        if addressChanged {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            // Reloading a request that was started a line ago re-fetches the
            // page that was on screen before it, which is exactly what moving
            // to the next game in the queue does: new launch URL, new token.
            if !addressChanged { webView.reload() }
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // The player webview is intentionally kept alive between presentations.
        if coordinator.role != .stream {
            coordinator.closePopups()
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

        if role == .searchResults {
            controller.addUserScript(WKUserScript(source: WebScripts.xboxSearchResultsJS,
                                                  injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true))
            return
        }
        guard role == .stream else { return }

        // The PWA spoof must land before any page script reads
        // navigator.standalone, so it goes in first, at document start.
        controller.addUserScript(WKUserScript(source: WebScripts.pwaStandaloneJS,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        // The rumble bridge must wrap createDataChannel before the page opens
        // its WebRTC session, so it has to run at document start.
        let settings = AppSettings.shared
        // The page has to be able to find a gamepad, and WKWebView cannot
        // show it the real one, so the bridge goes in before anything else
        // looks for a pad.
        controller.addUserScript(WKUserScript(source: WebScripts.gamepadBridgeJS,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(
            source: "window.__gsRumbleMode = \"\(settings.rumbleEnabled ? "page" : "off")\";"
                + "window.__gsRumbleScale = \(settings.rumbleIntensity);",
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
        // The input configuration leaves the page over the network, so the
        // wrapper has to be in place before the site builds its session.
        if settings.touchControls == .everyGame {
            controller.addUserScript(WKUserScript(source: WebScripts.touchInputJS,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
        }
        controller.addUserScript(WKUserScript(source: WebScripts.betterXCloudPrefsJS(
            global: AppSettings.shared.betterXCloudGlobalPreferences(),
            stream: AppSettings.shared.betterXCloudStreamPreferences()),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        // A pending reinstall cleans the page before the script sees it, so
        // the new copy cannot pick the old patch cache back up.
        if UserDefaults.standard.bool(forKey: "betterXCloud.purgePending") {
            UserDefaults.standard.set(false, forKey: "betterXCloud.purgePending")
            controller.addUserScript(WKUserScript(source: BetterXCloud.purgeJS,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
            AppLog.shared.info("betterxcloud", "the next page load starts from clean storage")
        }
        if let script = BetterXCloud.shared.cachedScript {
            // Better xCloud rewrites the site's own JavaScript bundle as it
            // loads, so it has to be in place before the page boots: given
            // the finished page it says "Failed to run Better xCloud" and
            // does nothing.
            controller.addUserScript(WKUserScript(source: script,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
        }
        // The skin has to land after Better xCloud's own stylesheet, so it
        // goes in at document end like the rest of the page dressing.
        if AppSettings.shared.matchStreamStyle {
            controller.addUserScript(WKUserScript(
                source: WebScripts.betterXCloudSkinJS(
                    accentRGB: AppSettings.shared.accent.rgbTriple
                ),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        }

        for source in [WebScripts.streamStateJS, WebScripts.streamChromeJS,
                       WebScripts.streamStatsJS, WebScripts.streamCommandsJS,
                       WebScripts.captureJS, WebScripts.clipJS,
                       WebScripts.pageSignalsJS,
                       WebScripts.autoStartJS] {
            controller.addUserScript(WKUserScript(source: source,
                                                  injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true))
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
                             UIGestureRecognizerDelegate {

        /// The last page signals written to the log. The page reports itself
        /// every two seconds, and a stream that runs for an hour would
        /// otherwise write the same five lines over and over.
        private var lastPageSignals = ""

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
        var onSearchResults: ((URL, [Game], String, String) -> Void)?
        var loadedURL: URL?
        var reloadToken = 0
        private weak var webView: WKWebView?
        private var signInPopups: [WKWebView] = []
        private let log = AppLog.shared

        init(role: Role, onSearchResults: ((URL, [Game], String, String) -> Void)? = nil) {
            self.role = role
            self.onSearchResults = onSearchResults
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
        }

        func closePopups() {
            for popup in signInPopups {
                popup.stopLoading()
                popup.navigationDelegate = nil
                popup.uiDelegate = nil
                popup.removeFromSuperview()
            }
            signInPopups.removeAll()
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
            case "xboxSearchResults":
                guard role == .searchResults,
                      let href = body["href"] as? String,
                      let sourceURL = URL(string: href),
                      sourceURL.scheme == "https",
                      sourceURL.host == "www.xbox.com",
                      sourceURL.path.contains("/play/search") else { return }
                let status = body["status"] as? String ?? "error"
                let message = body["message"] as? String ?? ""
                var seen = Set<String>()
                let rows = body["items"] as? [[String: Any]] ?? []
                let games = rows.compactMap { row -> Game? in
                    guard let id = row["id"] as? String,
                          (8...20).contains(id.count),
                          id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }),
                          seen.insert(id.uppercased()).inserted,
                          let slug = row["slug"] as? String, !slug.isEmpty,
                          slug.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) }),
                          let title = row["title"] as? String, !title.isEmpty else { return nil }
                    let poster = (row["image"] as? String).flatMap { URL(string: $0) }
                    let safePoster = poster.flatMap {
                        $0.scheme == "https" && $0.host == "store-images.s-microsoft.com" ? $0 : nil
                    }
                    return Game(id: id, slug: slug, title: title, tagline: "",
                                genre: "Cloud", posterURL: safePoster)
                }
                onSearchResults?(sourceURL, games, status, message)
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
            case "autoStartMiss":
                log.info("stream", "no cloud-play button matched; on the page: "
                        + (body["labels"] as? String ?? "nothing"))
            case "pageSignals":
                let href = body["href"] as? String ?? ""
                let standalone = body["standalone"] as? Bool ?? false
                let displayMode = body["displayMode"] as? Bool ?? false
                let serviceWorker = body["serviceWorker"] as? Bool ?? false
                let touchPoints = body["touchPoints"] as? Int ?? 0
                let platform = body["platform"] as? String ?? ""
                let userAgent = body["userAgent"] as? String ?? ""
                let better = body["bx"] as? String ?? ""
                // The host that will carry the stream, so the connection
                // check measures the machine the game will run on rather
                // than the website's CDN.
                if let region = body["region"] as? String, !region.isEmpty {
                    NetworkCheck.shared.rememberRegion(baseURI: region)
                }
                let buttons = (body["buttons"] as? [String] ?? []).joined(separator: " | ")
                let dialogs = (body["dialogs"] as? [String] ?? []).joined(separator: " | ")
                // The page reports itself every two seconds. Only a change is
                // worth five lines of log.
                let signature = "\(href)|\(standalone)|\(displayMode)|\(serviceWorker)|\(touchPoints)|\(platform)|\(better)|\(buttons)|\(dialogs)"
                guard signature != lastPageSignals else { return }
                lastPageSignals = signature
                log.info("stream", "page signals: standalone=\(standalone) "
                        + "displayMode=\(displayMode) serviceWorker=\(serviceWorker) "
                        + "touch=\(touchPoints) platform=\(platform)")
                log.info("stream", "page url: \(href)")
                if !userAgent.isEmpty { log.debug("stream", "page sees user agent: \(userAgent)") }
                if !better.isEmpty { log.info("stream", "better xcloud: \(better)") }
                if !buttons.isEmpty { log.info("stream", "buttons: \(buttons)") }
                if !dialogs.isEmpty { log.info("stream", "dialog: \(dialogs)") }
            case "videoState":
                log.debug("stream", "video: \(body["detail"] as? String ?? "")")
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
            case "clipChunk":
                StreamRecorder.shared.pageChunk(index: body["index"] as? Int ?? 0,
                                                base64: body["data"] as? String ?? "")
            case "clipEnd":
                StreamRecorder.shared.pageStopped()
            case "clipFailed":
                StreamRecorder.shared.pageFailed(body["message"] as? String ?? "")
            case "touchInput":
                StreamCoordinator.shared.touchInputReported(
                    state: body["state"] as? String ?? "",
                    detail: body["detail"] as? String ?? ""
                )
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

        /// iOS kills a web content process that uses too much memory, and the
        /// view it leaves behind is blank and inert. Without this the player
        /// looked frozen with no reason given.
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
            guard let url = navigationAction.request.url,
                  navigationAction.targetFrame == nil else { return nil }
            AppLog.shared.debug("web", "following popup to \(url.host ?? "a new window")")

            if role == .signIn {
                // Keep Microsoft sign-in popups as their own top-level WebView.
                // Redirecting target=_blank into the current page can discard
                // the popup's user-activation/WebAuthn context used by passkeys.
                // WebKit supplies the popup configuration, which retains the
                // shared persistent Xbox website data store; set it explicitly
                // so a passkey sign-in in the popup lands in the same session
                // the rest of the app reads.
                configuration.websiteDataStore = .default()
                let popup = WKWebView(frame: webView.bounds, configuration: configuration)
                popup.customUserAgent = XboxAuth.userAgent
                popup.navigationDelegate = self
                popup.uiDelegate = self
                popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                webView.addSubview(popup)
                signInPopups.append(popup)
                return popup
            }

            webView.load(navigationAction.request)
            return nil
        }

        @MainActor
        func webViewDidClose(_ webView: WKWebView) {
            guard let index = signInPopups.firstIndex(where: { $0 === webView }) else { return }
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
            signInPopups.remove(at: index)
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
