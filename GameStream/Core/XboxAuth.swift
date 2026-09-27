import Foundation
import Combine
import UIKit
import WebKit

/// Knows whether the user can actually stream, and nothing else.
///
/// The rule this class exists to enforce: GameStream never decides it is
/// signed in on its own. It asks the Xbox page whether a valid cloud-gaming
/// token exists. Guessing from cookie names is what made 1.x report a
/// successful sign-in and then drop the user on a sign-in page when they
/// pressed Play.
@MainActor
final class XboxAuth: NSObject, ObservableObject {
    static let shared = XboxAuth()

    /// Deliberately has no "checking" case.
    ///
    /// A re-check is not a different kind of session, and the root view picks
    /// its screen from this value. When checking was a state, every poll while
    /// the sign-in sheet was open swapped the screen out and back, which tore
    /// down the view owning the sheet and made it close and reopen on a loop.
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(gamertag: String)

        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }

        var gamertag: String? {
            if case .signedIn(let tag) = self, !tag.isEmpty { return tag }
            return nil
        }
    }

    @Published private(set) var state: State = .unknown
    /// Progress, shown as an indicator. It never changes which screen is up.
    @Published private(set) var isChecking = false
    /// Where the token was found, shown in Diagnostics so a failed sign-in can
    /// be explained instead of guessed at.
    @Published private(set) var tokenSource: String = ""
    @Published private(set) var tokenExpires: String = ""
    @Published private(set) var lastCheck: Date?
    @Published private(set) var lastError: String?

    /// A document on the xbox.com origin is required to read the site's
    /// localStorage. robots.txt is a real same-origin document and costs a
    /// fraction of what loading the full single-page app would.
    private static let probeURL = URL(string: "https://www.xbox.com/robots.txt")!
    static let playURL = URL(string: "https://www.xbox.com/play")!

    /// Matches mobile Safari, because Xbox's edge rejects the stock WebView
    /// user agent and serves an access-denied page instead of the site.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    private var probeView: WKWebView?
    private var probeLoaded = false
    private var pendingProbe: CheckedContinuation<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private let log = AppLog.shared

    private override init() {
        super.init()
    }

    // MARK: - Shared configuration

    /// One persistent data store for every webview in the app.
    ///
    /// Cookies *and* localStorage live in this store, so the sign-in view, the
    /// browser, and the player all see the same session. Anything ephemeral
    /// here would silently break streaming after a successful sign-in.
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Microsoft's sign-in may open its own window; the UI delegate keeps
        // that navigation in the same webview rather than losing it.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences
        return configuration
    }

    // MARK: - Checking

    /// Re-read the token. Safe to call often; it reuses one hidden webview.
    @discardableResult
    func refresh(reason: String) async -> State {
        isChecking = true
        defer { isChecking = false }
        log.debug("auth", "checking (\(reason))")

        await ensureProbeLoaded()

        guard let probeView else {
            lastError = "Could not create the authentication probe."
            log.error("auth", "probe webview unavailable")
            apply(.signedOut)
            return state
        }

        let result: Any?
        do {
            result = try await probeView.evaluateJavaScript(WebScripts.authProbeJS)
        } catch {
            lastError = error.localizedDescription
            log.error("auth", "probe failed: \(error.localizedDescription)")
            lastCheck = Date()
            apply(.signedOut)
            return state
        }

        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lastError = "The Xbox page returned an unreadable response."
            log.error("auth", "probe returned no usable payload")
            lastCheck = Date()
            apply(.signedOut)
            return state
        }

        let signedIn = payload["signedIn"] as? Bool ?? false
        let gamertag = (payload["gamertag"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        tokenSource = payload["source"] as? String ?? ""
        tokenExpires = payload["expires"] as? String ?? ""
        if let scriptError = payload["error"] as? String, !scriptError.isEmpty {
            lastError = scriptError
            log.warn("auth", "probe script error: \(scriptError)")
        } else {
            lastError = nil
        }

        lastCheck = Date()
        apply(signedIn ? .signedIn(gamertag: gamertag) : .signedOut)
        log.info("auth", signedIn
                 ? "signed in as \(gamertag.isEmpty ? "Xbox account" : gamertag) via \(tokenSource)"
                 : "no cloud-gaming token present")
        return state
    }

    /// Poll while a sign-in sheet is open so the app can dismiss it the moment
    /// the token appears, rather than asking the user to guess when to close it.
    func beginWatching() {
        guard watchTask == nil else { return }
        log.debug("auth", "watching for sign-in")
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                let state = await self.refresh(reason: "watch")
                if state.isSignedIn { return }
            }
        }
    }

    func endWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// Called when a webview reports it reached the site's post-login redirect.
    func noteAuthRedirect() {
        log.info("auth", "site completed its Microsoft sign-in redirect")
        Task { await refresh(reason: "auth redirect") }
    }

    // MARK: - Signing out

    func signOut() async {
        log.info("auth", "signing out")
        endWatching()
        apply(.signedOut)
        tokenSource = ""
        tokenExpires = ""

        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let matching = records.filter { record in
            let name = record.displayName.lowercased()
            return name.contains("xbox") || name.contains("microsoft")
                || name.contains("live") || name.contains("msauth")
        }
        await store.removeData(ofTypes: types, for: matching)

        probeLoaded = false
        probeView?.load(URLRequest(url: Self.probeURL))
        log.info("auth", "cleared \(matching.count) website data record(s)")
    }

    /// Publishes only genuine changes, so a repeated check does not churn the
    /// view tree for no reason.
    private func apply(_ next: State) {
        guard state != next else { return }
        state = next
    }

    // MARK: - Probe webview

    private func ensureProbeLoaded() async {
        if probeView == nil {
            let configuration = Self.makeConfiguration()
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 configuration: configuration)
            view.customUserAgent = Self.userAgent
            view.navigationDelegate = self
            view.isHidden = true
            view.isUserInteractionEnabled = false
            // A webview attached to a window loads reliably; a fully detached
            // one can be throttled by the system and never finish.
            attachToWindow(view)
            probeView = view
        }

        guard !probeLoaded, let probeView else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingProbe = continuation
            probeView.load(URLRequest(url: Self.probeURL))
            // Never let a hung network request block the UI forever.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, let pending = self.pendingProbe else { return }
                self.pendingProbe = nil
                self.log.warn("auth", "probe load timed out")
                pending.resume()
            }
        }
    }

    private func attachToWindow(_ view: WKWebView) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.windows.first else { return }
        window.addSubview(view)
        window.sendSubviewToBack(view)
    }

    private func finishProbeLoad(success: Bool, detail: String) {
        probeLoaded = success
        if !success { log.warn("auth", "probe load failed: \(detail)") }
        pendingProbe?.resume()
        pendingProbe = nil
    }
}

extension XboxAuth: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in finishProbeLoad(success: true, detail: "") }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                             withError error: Error) {
        let detail = error.localizedDescription
        Task { @MainActor in finishProbeLoad(success: false, detail: detail) }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        let detail = error.localizedDescription
        Task { @MainActor in finishProbeLoad(success: false, detail: detail) }
    }
}
