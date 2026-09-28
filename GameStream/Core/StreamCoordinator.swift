import Foundation
import Combine
import UIKit

/// The live numbers for one moment of a stream, read from WebRTC.
struct StreamStats: Equatable, Sendable {
    var fps = 0
    var bitrateKbps = 0
    var rttMs = 0
    var jitterMs = 0
    var packetsLost = 0
    var framesDropped = 0
    var decodeMs = 0
    var width = 0
    var height = 0
    var codec = ""

    init() {}

    init(payload: [String: Any]) {
        func number(_ key: String) -> Int { payload[key] as? Int ?? 0 }
        fps = number("fps")
        bitrateKbps = number("bitrateKbps")
        rttMs = number("rttMs")
        jitterMs = number("jitterMs")
        packetsLost = number("packetsLost")
        framesDropped = number("framesDropped")
        decodeMs = number("decodeMs")
        width = number("width")
        height = number("height")
        codec = (payload["codec"] as? String ?? "").uppercased()
    }

    var resolution: String { width > 0 && height > 0 ? "\(width)×\(height)" : "" }

    /// Connection quality, judged the way a player would: latency first,
    /// then whether frames are actually arriving.
    enum Quality { case good, fair, poor }

    var quality: Quality {
        if rttMs > 120 || fps < 30 { return .poor }
        if rttMs > 70 || fps < 50 { return .fair }
        return .good
    }
}

/// Owns a play session from the moment Play is pressed until the stream ends.
///
/// The phases exist so the interface can tell the truth about what is
/// happening. 1.x hid its loading overlay as soon as the launch page loaded
/// and had nowhere to show an error, so a failed session looked identical to a
/// black screen that was still connecting.
@MainActor
final class StreamCoordinator: ObservableObject {
    static let shared = StreamCoordinator()

    enum Phase: Equatable {
        case idle
        case connecting(String)
        case playing
        case failed(String)

        var isActive: Bool { self != .idle }
    }

    @Published private(set) var game: Game?
    @Published private(set) var phase: Phase = .idle
    /// The result of the last HUD command, shown briefly over the stream.
    /// Digging a log out of Settings after the fact is not a reasonable way
    /// to find out whether a button you just pressed did anything.
    @Published private(set) var notice: String?
    private var noticeTask: Task<Void, Never>?
    private var leaveCheck: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    /// Running totals, so a session can report how it actually played.
    private var sampleCount = 0
    private var fpsTotal = 0
    private var rttTotal = 0
    private var bitrateTotal = 0
    private var poorSince: Date?
    private var reducedQuality = false
    /// Bumped when the player asks for the overlay.
    @Published var overlayRequest = 0

    @Published private(set) var resolution: String = ""
    /// Bumping this asks the player's webview to reload the launch page.
    @Published private(set) var reloadToken = 0
    /// The live WebRTC numbers, or nil before the first sample arrives.
    @Published private(set) var stats: StreamStats?

    private var startedAt: Date?
    private var watchdog: Task<Void, Never>?
    private let log = AppLog.shared

    private init() {}

    var launchURL: URL {
        game?.launchURL ?? XboxAuth.playURL
    }

    // MARK: - Session control

    func play(_ game: Game) {
        guard XboxAuth.shared.state.isSignedIn else {
            log.warn("stream", "refused to launch \(game.title): not signed in")
            phase = .failed("Sign in to your Microsoft account before starting a game.")
            self.game = game
            return
        }

        log.info("stream", "launching \(game.title) (\(game.id))")
        self.game = game
        resolution = ""
        startedAt = Date()
        phase = .connecting("Starting \(game.title)")
        LibraryStore.shared.noteLaunch(game)
        UIApplication.shared.isIdleTimerDisabled = true
        // A new session deserves a clean attempt at every rumble route, even
        // one that refused to start earlier.
        ControllerRumble.shared.retryAllRoutes(reason: "stream start")
        sampleCount = 0
        fpsTotal = 0
        rttTotal = 0
        bitrateTotal = 0
        poorSince = nil
        reducedQuality = false
        reconnectAttempts = 0
        SessionGuard.shared.begin()
        startWatchdog()

        // Measuring afterwards would be pointless; this runs alongside the
        // launch and only speaks up when the answer is bad.
        if AppSettings.shared.preflightCheck {
            Task { [weak self] in
                let reading = await NetworkCheck.shared.measure()
                guard let self, reading.isPoor else { return }
                self.show(notice: reading.verdict)
            }
        }
    }

    func retry() {
        guard let game else { return }
        log.info("stream", "retrying \(game.title)")
        phase = .connecting("Reconnecting to \(game.title)")
        reloadToken &+= 1
        startWatchdog()
    }

    /// Leaves the stream and writes the session into Activity.
    func exit() {
        rendererChanged(to: .none)
        watchdog?.cancel()
        watchdog = nil
        leaveCheck?.cancel()
        leaveCheck = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        SessionGuard.shared.end()
        ControllerRumble.shared.stop()
        // A clip in progress belongs to the session that was running. Left
        // alone it keeps recording the app with no button on screen to stop
        // it, and the footage is never written.
        if StreamRecorder.shared.isRecording {
            Task { _ = await StreamRecorder.shared.stop() }
        }
        // The player webview is kept alive across presentations, so this is
        // the point where the page has to actually be shut down.
        XboxWebView.Registry.shared.release()
        UIApplication.shared.isIdleTimerDisabled = AppSettings.shared.keepAwake

        if let game, let startedAt {
            let seconds = Date().timeIntervalSince(startedAt)
            // Anything shorter than this is a mis-tap, not a play session.
            if seconds >= 15 {
                let samples = max(sampleCount, 1)
                LibraryStore.shared.record(
                    PlayRecord(gameID: game.id, title: game.title,
                               startedAt: startedAt, seconds: seconds,
                               averageFPS: sampleCount > 0 ? fpsTotal / samples : 0,
                               averageLatencyMs: sampleCount > 0 ? rttTotal / samples : 0,
                               averageBitrateKbps: sampleCount > 0 ? bitrateTotal / samples : 0)
                )
                log.info("stream", "session ended after \(Int(seconds))s")
            }
        }

        self.startedAt = nil
        game = nil
        resolution = ""
        stats = nil
        phase = .idle
    }

    /// Asked for by a double tap on the video, or the grip.
    func requestOverlay() { overlayRequest &+= 1 }

    /// Ends the Xbox session itself rather than only leaving the app.
    ///
    /// Closing the player stops streaming, but the console session stays open
    /// for a while and the next launch resumes into it. Pressing the site's
    /// own quit is the only way to end it deliberately.
    func quitGame() {
        log.info("stream", "quitting the game")
        show(notice: "Ending the session on Xbox…")
        XboxWebView.Registry.shared.run(
            "window.__gsCommand && window.__gsCommand('quit');"
        )
        // The page needs a moment to send the quit before the view goes
        // away, and it has to open the guide to reach the control at all.
        // Leaving before it gets there ends the app's session and leaves the
        // console one running, which is the whole thing this avoids.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2600))
            await MainActor.run { self?.exit() }
        }
    }

    /// Says the connection cannot hold the quality, once per session.
    ///
    /// It does not claim to have fixed it. The bitrate ceiling is written
    /// into the session description when the connection is negotiated, so
    /// nothing set during a session changes what is being sent — an earlier
    /// build wrote the preference mid-stream and reported success, which was
    /// simply untrue. Lowering it for real needs a reconnect.
    func reduceQuality(reason: String) {
        guard !reducedQuality else { return }
        reducedQuality = true
        log.warn("stream", "the stream is struggling: \(reason)")
        let cap = AppSettings.shared.maxBitrateMbps
        show(notice: cap > 0
             ? "The connection is struggling because \(reason). Reconnect to apply "
                + "your \(cap) Mbps limit, or lower it in Settings."
             : "The connection is struggling because \(reason). Setting a bitrate "
                + "limit in Settings and reconnecting would steady it.")
    }

    /// Ten seconds of genuinely bad numbers, not one unlucky sample.
    private func considerReducingQuality(for value: StreamStats) {
        guard AppSettings.shared.adaptiveQuality, !reducedQuality else { return }
        let bad = value.rttMs > 140 || value.packetsLost > 40 || value.fps < 35
        guard bad else {
            poorSince = nil
            return
        }
        let since = poorSince ?? Date()
        poorSince = since
        guard Date().timeIntervalSince(since) >= 10 else { return }
        reduceQuality(reason: "the connection could not hold the quality")
    }

    /// Rejoins after a drop, backing off and giving up rather than looping.
    func connectionLost(_ detail: String) {
        guard AppSettings.shared.autoReconnect, reconnectAttempts < 3 else {
            phase = .failed(detail.isEmpty ? "The stream was interrupted." : detail)
            return
        }
        reconnectAttempts += 1
        let wait = Double(reconnectAttempts) * 2
        log.warn("stream", "connection lost (\(detail)); reconnecting in \(Int(wait))s "
                 + "(attempt \(reconnectAttempts) of 3)")
        phase = .connecting("Reconnecting… attempt \(reconnectAttempts) of 3")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.retry() }
        }
    }

    /// Starts the next queued game without returning to the library first.
    func playNextInQueue() {
        guard let next = LibraryStore.shared.takeNextFromQueue() else {
            exit()
            return
        }
        exit()
        play(next)
    }

    // MARK: - Reports from the page

    func loadingChanged(_ loading: Bool) {
        guard case .connecting = phase, loading else { return }
        log.debug("stream", "page navigation started")
    }

    func pageChanged(kind: String, href: String, role: XboxWebView.Role) {
        if role == .signIn || kind == "auth" {
            if kind == "auth" { XboxAuth.shared.noteAuthRedirect() }
            return
        }
        guard role == .stream else { return }
        log.debug("stream", "page is now \(kind)")

        // Being bounced back to the store or sign-in page means the launch did
        // not take. Saying so beats leaving a spinner on screen.
        if kind == "login", case .connecting = phase {
            phase = .failed("Xbox asked for a sign-in. Your session may have expired.")
            Task { await XboxAuth.shared.refresh(reason: "stream bounced to login") }
        }

        // Quitting from the Xbox guide, or Better xCloud's "back to home",
        // navigates the page away from the launch URL. The player was still
        // on screen showing xbox.com, so leaving a game dumped you on the
        // cloud gaming website instead of back in the app.
        if phase == .playing, kind != "launch" {
            confirmLeftTheGame(reportedKind: kind)
        }
    }

    /// Ending a live session on one navigation report is too eager: a
    /// single-page route change can fire and then settle straight back on
    /// the launch URL, and killing a running game for that would be far
    /// worse than showing the website for a moment. Ask the page again.
    private func confirmLeftTheGame(reportedKind: String) {
        guard leaveCheck == nil else { return }
        leaveCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, !Task.isCancelled else { return }
            XboxWebView.Registry.shared.evaluate("String(location.href)") { href in
                Task { @MainActor in
                    self.leaveCheck = nil
                    guard self.phase == .playing else { return }
                    guard !href.contains("/play/launch") else {
                        self.log.debug("stream", "the page came back to the game")
                        return
                    }
                    self.log.info("stream", "the page left the game "
                                  + "(\(reportedKind)); returning to the app")
                    self.exit()
                }
            }
        }
    }

    func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.notice = nil }
        }
    }

    func statsUpdated(_ value: StreamStats) {
        stats = value
        if phase == .playing {
            sampleCount += 1
            fpsTotal += value.fps
            rttTotal += value.rttMs
            bitrateTotal += value.bitrateKbps
            considerReducingQuality(for: value)
        }
        // The page knows the true frame size; use it rather than whatever the
        // launch page reported when the picture first appeared.
        if !value.resolution.isEmpty, resolution != value.resolution {
            resolution = value.resolution
        }
    }

    /// Which engine is actually drawing frames right now.
    ///
    /// Recorded rather than assumed. "Is this still a browser?" is a
    /// question the app should be able to answer from what it is doing, not
    /// from what it intended.
    enum Renderer: String {
        case none = "Nothing is streaming"
        case webKit = "WebKit — the site's player"
        case native = "Metal — native WebRTC, no WebKit"
    }

    @Published private(set) var renderer: Renderer = .none

    var rendererDescription: String { renderer.rawValue }

    func rendererChanged(to value: Renderer) {
        renderer = value
        log.info("stream", "renderer: \(value.rawValue)")
    }

    /// Pushes the picture settings into a running web player.
    ///
    /// The native player reads the same settings directly, so this is a
    /// no-op there rather than a second code path.
    func applyEnhancements() {
        guard renderer == .webKit else { return }
        let configuration = AppSettings.shared.enhancerConfiguration()
        guard let data = try? JSONEncoder().encode(configuration),
              let json = String(data: data, encoding: .utf8) else { return }
        XboxWebView.Registry.shared.run(
            "window.__gsEnhanceApply && window.__gsEnhanceApply(\(json));"
        )
    }

    /// What the enhancement layer saw in the session description.
    ///
    /// This is the only truthful source for which codecs are actually on
    /// offer, which is why it is recorded rather than inferred from a
    /// setting the user turned on.
    @Published private(set) var offeredCodecs = ""

    func enhancementReported(codecs: String, notes: String) {
        if !codecs.isEmpty { offeredCodecs = codecs }
        log.info("stream", "codecs: \(codecs)" + (notes.isEmpty ? "" : " — \(notes)"))
    }

    /// Presses the site's Xbox guide button.
    func pressGuide() {
        log.info("stream", "pressing the Xbox guide")
        XboxWebView.Registry.shared.run("window.__gsCommand && window.__gsCommand('guide');")
    }

    func streamStarted(width: Int, height: Int) {
        rendererChanged(to: .webKit)
        watchdog?.cancel()
        watchdog = nil
        // A reconnect that worked has spent none of the budget. Counting
        // attempts for the lifetime of the session meant the fourth drop of
        // a long evening was never rejoined, however well the first three
        // recoveries went.
        reconnectAttempts = 0
        if width > 0, height > 0 {
            resolution = "\(width)×\(height)"
        }
        guard phase != .playing else { return }
        phase = .playing
        log.info("stream", "playing\(resolution.isEmpty ? "" : " at \(resolution)")")
    }

    func streamFailed(message: String) {
        // Losing a stream that was running is a disconnection, not a failed
        // launch, and it is the case worth rejoining automatically.
        if phase == .playing {
            connectionLost(message.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        guard case .connecting = phase else { return }
        watchdog?.cancel()
        watchdog = nil
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .failed(detail.isEmpty ? "The stream could not be started." : detail)
        log.warn("stream", "failed: \(detail)")
    }

    /// A stream that never produces a picture should say so rather than
    /// spinning indefinitely.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(75))
            guard !Task.isCancelled, let self else { return }
            guard case .connecting = self.phase else { return }
            self.phase = .failed(
                "Xbox did not start the stream. This usually means the service is busy, "
                + "or the game is not available in your region."
            )
            self.log.warn("stream", "watchdog timed out")
        }
    }
}
