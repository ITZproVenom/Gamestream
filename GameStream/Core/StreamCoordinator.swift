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

    /// Whether the player has to sign in before the game can be tried
    /// again.
    ///
    /// "Try again" cannot fix a session that is not there: the button did
    /// nothing at all, and the player had no way to sign in from the screen
    /// that told them to.
    @Published private(set) var needsSignIn = false

    /// Where in the launch sequence the player currently is, so the loading
    /// screen can show real progress instead of one spinner for everything.
    enum ConnectStage: Equatable {
        case launching, connecting, startingSession

        var index: Int {
            switch self {
            case .launching: return 0
            case .connecting: return 1
            case .startingSession: return 2
            }
        }
    }

    @Published private(set) var connectStage: ConnectStage = .launching

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
    /// The last reading of the connection's lost-packet count, so the change
    /// between two readings can be looked at.
    private var lastPacketsLost: Int?
    /// Bumped when the player asks for the overlay.
    @Published var overlayRequest = 0

    @Published private(set) var resolution: String = ""
    /// Bumping this asks the player's webview to reload the launch page.
    @Published private(set) var reloadToken = 0
    /// The live WebRTC numbers, or nil before the first sample arrives.
    @Published private(set) var stats: StreamStats?

    private(set) var startedAt: Date?
    /// The game that came off the queue to be played next, kept until the
    /// launch either starts or fails.
    private var queuedNext: Game?
    private var watchdog: Task<Void, Never>?
    /// The last page written to the log, so a page that reports itself every
    /// two seconds does not fill the log with the same line.
    private var lastLoggedPage = ""
    private let log = AppLog.shared

    private init() {}

    var launchURL: URL {
        game?.launchURL ?? XboxAuth.playURL
    }

    // MARK: - Session control

    /// The game waiting for a server to be chosen, when the player asked
    /// to be shown the servers before a launch.
    @Published var serverPickerGame: Game?

    /// Puts a game back when the server picker is dismissed.
    ///
    /// The queue's next game is taken off the queue before it is played, so
    /// a picker that is cancelled would lose it: the game would be neither
    /// playing nor queued.
    func serverPickerCancelled() {
        guard let game = serverPickerGame else { return }
        serverPickerGame = nil
        if queuedNext?.id == game.id, let next = queuedNext {
            queuedNext = nil
            LibraryStore.shared.putBackOnQueue(next)
            log.info("stream", "the server picker was cancelled; "
                     + "\(next.title) went back on the queue")
        }
    }

    func play(_ game: Game) {
        // When the player wants to pick a server, the choice is made before
        // anything starts: the session is created against the server that
        // was picked, and it cannot be moved afterwards.
        // The picker is not offered while a game is running: the player
        // would be left looking at the old game with a sheet over it, and
        // the session cannot be moved to another server once it exists.
        if AppSettings.shared.pickServerBeforePlay, !CloudServers.shared.servers.isEmpty,
           !phase.isActive {
            serverPickerGame = game
            return
        }
        launch(game, on: nil)
    }

    /// Starts a game, on the server the player chose.
    func launch(_ game: Game, on server: CloudServer?) {
        serverPickerGame = nil
        if let server {
            CloudServers.shared.chosen = server.name
            AppLog.shared.info("servers", "playing on \(server.shortName)")
            // The player page is kept alive between games, so the choice has
            // to be handed to the page that is already there - not only to
            // the next one that is made.
            XboxWebView.Registry.shared.run(
                "window.__gsSetCloudChoice && window.__gsSetCloudChoice(\""
                    + server.name + "\");")
        }
        guard XboxAuth.shared.state.isSignedIn else {
            log.warn("stream", "refused to launch \(game.title): not signed in")
            needsSignIn = true
            phase = .failed("Sign in to your Microsoft account before starting a game.")
            self.game = game
            return
        }

        // A launch that is allowed to go ahead clears the sign-in flag: it
        // was only ever set, so one refused launch left every later failure
        // screen offering "Sign in" instead of "Try again", even after the
        // player had signed in and the failure was something else entirely.
        needsSignIn = false
        log.info("stream", "launching \(game.title) (\(game.id))")
        // Whatever was watching the previous session has to stop watching:
        // the leave check would end the new game the moment the page
        // reported itself, and the reconnect would start a second session.
        watchdog?.cancel()
        watchdog = nil
        leaveCheck?.cancel()
        leaveCheck = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        self.game = game
        resolution = ""
        startedAt = Date()
        phase = .connecting("Starting \(game.title)")
        connectStage = .launching
        LibraryStore.shared.noteLaunch(game)
        UIApplication.shared.isIdleTimerDisabled = true
        // A new session deserves a clean attempt at every rumble route, even
        // one that refused to start earlier.
        ControllerRumble.shared.retryAllRoutes(reason: "stream start")
        resetSessionMetrics()
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

    /// Reloads the launch page for the game that is already selected.
    ///
    /// `resettingBudget` is what separates the player pressing "Try again"
    /// from the app rejoining on its own. Without it, the three automatic
    /// attempts were spent for the rest of the session: a manual retry
    /// afterwards worked, but the next drop was reported as an error instead
    /// of being rejoined. The quality latch has the same problem in reverse,
    /// so a fresh attempt starts with fresh measurements.
    func retry(resettingBudget: Bool = true) {
        guard let game else { return }
        log.info("stream", "retrying \(game.title)")
        if resettingBudget {
            reconnectAttempts = 0
            reconnectTask?.cancel()
            reconnectTask = nil
        }
        reducedQuality = false
        poorSince = nil
        phase = .connecting("Reconnecting to \(game.title)")
        connectStage = .launching
        reloadToken &+= 1
        startWatchdog()
    }

    /// Leaves the stream and writes the session into Activity.
    func exit() {
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

        recordFinishedSession()

        self.startedAt = nil
        game = nil
        resolution = ""
        stats = nil
        // Leaving with the enhancement menu open used to carry that belief
        // into the next session, so the button that opens it tried to close
        // something that was not there and appeared to do nothing. A notice
        // left on screen would likewise reappear over the next launch.
        enhancementMenuOpen = false
        offeredCodecs = ""
        codecOutcome = ""
        touchInputOutcome = ""
        notice = nil
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
        XboxWebView.Registry.shared.run(
            "window.__gsCommand && window.__gsCommand('quit');"
        )
        // The page needs a moment to send the quit before the view goes away.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
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
    ///
    /// The lost packets are counted by the connection for the whole session,
    /// so the total says nothing about how the connection is doing *now*:
    /// a session that lost forty packets in its first minute was told its
    //// connection was bad for the rest of its life, however well it ran
    /// afterwards. What matters is how many were lost in the last second,
    /// so the change between two readings is what is looked at.
    private func considerReducingQuality(for value: StreamStats) {
        guard AppSettings.shared.adaptiveQuality, !reducedQuality else { return }
        let lostNow: Int
        if let previous = lastPacketsLost, value.packetsLost >= previous {
            lostNow = value.packetsLost - previous
        } else {
            // The count went backwards - the connection was replaced - so
            // this reading says nothing about the old one.
            lostNow = 0
        }
        lastPacketsLost = value.packetsLost
        let bad = value.rttMs > 140 || lostNow > 8 || value.fps < 35
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
            await MainActor.run {
                guard let self else { return }
                guard AppSettings.shared.autoReconnect else {
                    self.reconnectTask = nil
                    self.phase = .failed("Automatic reconnection is off. You can retry manually.")
                    self.log.info("stream", "scheduled reconnect skipped because auto-reconnect was turned off")
                    return
                }
                self.retry(resettingBudget: false)
            }
        }
    }

    /// Starts the next queued game without returning to the library first.
    ///
    /// This deliberately never passes through `.idle`. The player is a full
    /// screen cover driven by whether a session is active, so ending one and
    /// starting the next in the same turn asked SwiftUI to dismiss and
    /// re-present it at once: the dismissal won, and taking the next game in
    /// the queue dropped the player back to the library with a session
    /// starting behind it. The session is written to Activity, the counters
    /// are reset and the same page is pointed at the new game instead.
    func playNextInQueue() {
        // The game is taken off the queue but remembered, so a launch that
        // never starts can put it back. Taking it off for good meant a
        // failed launch quietly lost the game from the queue.
        guard let next = LibraryStore.shared.takeNextFromQueue() else {
            exit()
            return
        }
        queuedNext = next
        guard XboxAuth.shared.state.isSignedIn else {
            exit()
            launch(next, on: nil)
            return
        }

        log.info("stream", "moving on to \(next.title) (\(next.id))")
        // The session that is ending is recorded and tidied up here; the
        // new one is started by launch(), so there is only one place that
        // starts a game. Two places meant every change to the start of a
        // game had to be made twice, and once was not.
        recordFinishedSession()
        leaveCheck?.cancel()
        leaveCheck = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        if StreamRecorder.shared.isRecording {
            Task { _ = await StreamRecorder.shared.stop() }
        }
        ControllerRumble.shared.stop()
        stats = nil
        notice = nil
        enhancementMenuOpen = false
        offeredCodecs = ""
        codecOutcome = ""
        touchInputOutcome = ""
        launch(next, on: nil)
    }

    private func resetSessionMetrics() {
        sampleCount = 0
        fpsTotal = 0
        rttTotal = 0
        bitrateTotal = 0
        poorSince = nil
        reducedQuality = false
        lastPacketsLost = nil
        reconnectAttempts = 0
    }

    /// Writes the session that just finished into Activity, if it was long
    /// enough to count as one.
    private func recordFinishedSession() {
        guard let game, let startedAt else { return }
        let seconds = Date().timeIntervalSince(startedAt)
        // Anything shorter than this is a mis-tap, not a play session.
        guard seconds >= 15 else { return }
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
        // The page reports itself every two seconds, so the same page was
        // written to the log over and over for the length of a session. Only
        // a page that actually changed is worth a line.
        let page = "\(kind)|\(href)"
        if page == lastLoggedPage { return }
        lastLoggedPage = page
        log.debug("stream", "page is now \(kind) (\(href))")

        // Being bounced back to the store or sign-in page means the launch did
        // not take. Saying so beats leaving a spinner on screen.
        if kind == "login", case .connecting = phase {
            needsSignIn = true
            phase = .failed("Xbox asked for a sign-in. Your session may have expired.")
            // The session is not merely stale - the service has just turned
            // it away - so it is ended rather than checked again. A check
            // finds the same token in the storage and reports a session
            // that the service has already refused, and the next launch
            // fails the same way.
            Task { await XboxAuth.shared.signOut() }
        }
        // A launch URL that settles on the store page (/play/games, /products)
        // or the /play home never starts a stream by itself; the auto-start
        // script clicks the site's Play button there instead, and the watchdog
        // fails the session if nothing starts.

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
                    guard !href.contains("/play/launch"), !href.contains("/stream/") else {
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

    /// Whether the enhancement's menu is believed to be open, so the same
    /// button can put it away again. Its dialog is hard to dismiss by touch
    /// in this webview, so leaving the only exit inside it is a trap.
    @Published private(set) var enhancementMenuOpen = false

    /// Opens or closes the enhancement's menu.
    func toggleEnhancementMenu() {
        if enhancementMenuOpen {
            closeEnhancementMenu()
            enhancementMenuOpen = false
        } else {
            openEnhancementMenu()
            enhancementMenuOpen = true
        }
    }

    /// What the enhancement layer saw in the session description.
    ///
    /// This is the only truthful source for which codecs are actually on
    /// offer, which is why it is recorded rather than inferred from a
    /// setting the user turned on.
    @Published private(set) var offeredCodecs = ""

    /// What the layer did with the offer, in its own words. Logged only
    /// before, so whether asking for H.265 had worked was invisible unless
    /// the log was exported.
    @Published private(set) var codecOutcome = ""

    /// What forcing touch input actually did, in the page's own words.
    ///
    /// Asking is not the same as getting. The server decides whether it has a
    /// touch layout for a game, so this records what happened instead of
    /// letting a switch in Settings imply a result.
    @Published private(set) var touchInputOutcome = ""

    /// What the session was actually asked for.
    ///
    /// The page reports this when it rewrites the session request, and it
    /// is the only way to tell whether a setting reached the service at
    /// all: a setting that did nothing and one that worked used to look the
    /// same from here.
    func touchInputReported(state: String, detail: String) {
        let text = detail.isEmpty ? state : detail
        guard !text.isEmpty, touchInputOutcome != text else { return }
        touchInputOutcome = text
        log.info("stream", "session: \(text)")
    }

    func enhancementReported(codecs: String, notes: String) {
        if !codecs.isEmpty { offeredCodecs = codecs }
        if !notes.isEmpty { codecOutcome = notes }
        log.info("stream", "codecs: \(codecs)" + (notes.isEmpty ? "" : " - \(notes)"))
    }

    /// Opens the streaming enhancement's own menu.
    /// Opens Better xCloud's own menu.
    ///
    /// The app used to open it and then try to make it look like the app:
    /// rules for its panels, its dropdowns, its buttons, and a tab to click
    /// first. The script rebuilds all of that whenever it likes and writes
    /// its own stylesheet over the app's, so the result changed every time
    /// and never settled.
    ///
    /// Now the page is asked to do what its own button does - focus a tab,
    /// then show the dialog - and the app only makes sure the menu is
    /// scrolled into view. Its own look is its own.
    func openEnhancementMenu() {
        log.info("stream", "opening the enhancement menu")
        XboxWebView.Registry.shared.run(
            "window.__gsCommand ? '' : 'the command bridge is not installed on this page';"
        )
        XboxWebView.Registry.shared.run("window.__gsCommand && window.__gsCommand('bxMenu');")
    }

    /// Closes the menu and clears anything it left over the game.
    /// Dismissing it by tapping outside leaves its dimming overlay in the
    /// page, which swallows every touch meant for the stream.
    func closeEnhancementMenu() {
        log.info("stream", "closing the enhancement menu")
        XboxWebView.Registry.shared.run("window.__gsCommand && window.__gsCommand('bxClose');")
    }

    /// Presses the site's Xbox guide button.
    func pressGuide() {
        log.info("stream", "pressing the Xbox guide")
        XboxWebView.Registry.shared.run(
            "window.__gsCommand ? '' : 'the command bridge is not installed on this page';"
        )
        XboxWebView.Registry.shared.run("window.__gsCommand && window.__gsCommand('guide');")
    }

    func streamStarted(width: Int, height: Int) {
        // Ignore late messages from a webview whose session has already ended.
        // Without this guard, a delayed page callback could resurrect an exited
        // stream and present a blank player over the library.
        guard case .connecting = phase else { return }
        watchdog?.cancel()
        watchdog = nil
        if width > 0, height > 0 {
            resolution = "\(width)×\(height)"
        }
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
        // A game that came off the queue and never started goes back on it.
        // Losing it meant a failed launch quietly removed it from the
        // player's queue.
        if let next = queuedNext {
            queuedNext = nil
            LibraryStore.shared.putBackOnQueue(next)
        }
    }

    /// A stream that never produces a picture should say so rather than
    /// spinning indefinitely.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(75))
            guard !Task.isCancelled, let self else { return }
            guard case .connecting = self.phase else { return }
            // The failure goes through the same path as any other, so a
            // game taken off the queue to be played next is put back: the
            // watchdog used to fail the session by itself, and the game
            // quietly left the queue.
            self.streamFailed(
                message: "Xbox did not start the stream. This usually means the service is busy, "
                + "or the game is not available in your region."
            )
            self.log.warn("stream", "watchdog timed out")
        }
    }
}
