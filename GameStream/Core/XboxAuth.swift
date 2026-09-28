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
    /// Never persisted and never printed.
    private(set) var xstsToken: String?
    @Published private(set) var tokenSource: String = ""
    @Published private(set) var tokenExpires: String = ""
    @Published private(set) var lastCheck: Date?
    @Published private(set) var lastError: String?

    /// A document on the xbox.com origin is required to read the site's
    /// localStorage. robots.txt is a real same-origin document and costs a
    /// fraction of what loading the full single-page app would, but a
    /// `text/plain` document is not guaranteed to expose storage, so the full
    /// page is kept as a fallback rather than assumed unnecessary.
    private static let probeCandidates: [URL] = [
        URL(string: "https://www.xbox.com/robots.txt")!,
        URL(string: "https://www.xbox.com/play")!
    ]
    static let playURL = URL(string: "https://www.xbox.com/play")!

    /// Matches mobile Safari, because Xbox's edge rejects the stock WebView
    /// user agent and serves an access-denied page instead of the site.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    private var probeView: WKWebView?
    private var probeLoaded = false
    private var probeIndex = 0
    private var probeLoading = false
    /// Every caller waiting on the current load. A single continuation slot
    /// would be overwritten when two checks overlap, and the overwritten one
    /// would never resume, hanging the app on "Checking your Xbox session".
    private var probeWaiters: [CheckedContinuation<Void, Never>] = []
    /// The in-flight check, so overlapping callers share one result instead of
    /// racing each other through the same webview.
    private var refreshTask: Task<State, Never>?
    private var watchTask: Task<Void, Never>?
    private var lastRedirectNote: Date?
    private let log = AppLog.shared

    private var probeURL: URL {
        Self.probeCandidates[min(probeIndex, Self.probeCandidates.count - 1)]
    }

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
    ///
    /// Calls made while a check is running join that check. Launch, the scene
    /// becoming active and the sign-in watcher all fire at once, and letting
    /// them each drive the probe independently is what makes the shared
    /// continuation slot collide.
    @discardableResult
    func refresh(reason: String) async -> State {
        if let existing = refreshTask {
            log.debug("auth", "joining the check already running (\(reason))")
            return await existing.value
        }
        let task = Task { [weak self] () -> State in
            guard let self else { return .unknown }
            return await self.performRefresh(reason: reason)
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh(reason: String) async -> State {
        isChecking = true
        defer { isChecking = false }
        log.debug("auth", "checking (\(reason))")

        await ensureProbeLoaded()
        // A document that never loaded cannot be asked anything, so move to
        // the next probe URL before giving up on the session.
        if !probeLoaded, advanceProbeCandidate() {
            await ensureProbeLoaded()
        }

        guard let probeView else {
            lastError = "Could not create the authentication probe."
            log.error("auth", "probe webview unavailable")
            apply(.signedOut)
            return state
        }

        var result: Any?
        do {
            result = try await probeView.evaluateJavaScript(WebScripts.authProbeJS)
            // A document with no reachable storage answers with an error
            // rather than a verdict; the full page always has storage.
            if storageUnavailable(in: result), advanceProbeCandidate() {
                await ensureProbeLoaded()
                result = try await probeView.evaluateJavaScript(WebScripts.authProbeJS)
            }
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
        // Memory only. This is a bearer token for the account; it is not
        // written to UserDefaults, not logged, and not included in exports.
        xstsToken = payload["token"] as? String
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
    ///
    /// The site bounces through /auth/msa repeatedly while it settles, so this
    /// arrives in bursts. Checking on every one of them fills the diagnostics
    /// log with duplicates without ever learning anything new.
    func noteAuthRedirect() {
        if let last = lastRedirectNote, Date().timeIntervalSince(last) < 1.5 { return }
        lastRedirectNote = Date()
        log.info("auth", "site completed its Microsoft sign-in redirect")
        Task { await refresh(reason: "auth redirect") }
    }

    // MARK: - Signing out

    func signOut() async {
        log.info("auth", "signing out")
        endWatching()
        apply(.signedOut)
        xstsToken = nil
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
        probeView?.load(URLRequest(url: probeURL))
        log.info("auth", "cleared \(matching.count) website data record(s)")
    }

    /// Publishes only genuine changes, so a repeated check does not churn the
    /// view tree for no reason.
    private func apply(_ next: State) {
        guard state != next else { return }
        state = next
    }

    /// True when the probe answered "I could not read storage" instead of
    /// "there is no token", which are very different things.
    private func storageUnavailable(in result: Any?) -> Bool {
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["signedIn"] as? Bool != true,
              let error = payload["error"] as? String, !error.isEmpty else { return false }
        let detail = error.lowercased()
        return detail.contains("security") || detail.contains("storage")
            || detail.contains("denied") || detail.contains("access")
    }

    private func advanceProbeCandidate() -> Bool {
        guard probeIndex + 1 < Self.probeCandidates.count else { return false }
        probeIndex += 1
        probeLoaded = false
        log.warn("auth", "session probe falling back to \(probeURL.path)")
        return true
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
            probeWaiters.append(continuation)
            guard !probeLoading else { return }
            probeLoading = true
            probeView.load(URLRequest(url: probeURL))
            // Never let a hung network request block the UI forever.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, self.probeLoading else { return }
                self.log.warn("auth", "probe load timed out")
                self.finishProbeLoad(success: false, detail: "timed out")
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
        guard probeLoading else { return }
        probeLoading = false
        probeLoaded = success
        if !success { log.warn("auth", "probe load failed: \(detail)") }
        let waiters = probeWaiters
        probeWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
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
