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
        startWatchdog()
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
        watchdog?.cancel()
        watchdog = nil
        ControllerRumble.shared.stop()
        // The player webview is kept alive across presentations, so this is
        // the point where the page has to actually be shut down.
        XboxWebView.Registry.shared.release()
        UIApplication.shared.isIdleTimerDisabled = AppSettings.shared.keepAwake

        if let game, let startedAt {
            let seconds = Date().timeIntervalSince(startedAt)
            // Anything shorter than this is a mis-tap, not a play session.
            if seconds >= 15 {
                LibraryStore.shared.record(
                    PlayRecord(gameID: game.id, title: game.title,
                               startedAt: startedAt, seconds: seconds)
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
    }

    func statsUpdated(_ value: StreamStats) {
        stats = value
        // The page knows the true frame size; use it rather than whatever the
        // launch page reported when the picture first appeared.
        if !value.resolution.isEmpty, resolution != value.resolution {
            resolution = value.resolution
        }
    }

    /// Opens the streaming enhancement's own menu.
    func openEnhancementMenu() {
        log.info("stream", "opening the enhancement menu")
        XboxWebView.Registry.shared.run(
            "window.__gsCommand ? '' : 'the command bridge is not installed on this page';"
        )
        XboxWebView.Registry.shared.run("window.__gsCommand && window.__gsCommand('bxMenu');")
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
        watchdog?.cancel()
        watchdog = nil
        if width > 0, height > 0 {
            resolution = "\(width)×\(height)"
        }
        guard phase != .playing else { return }
        phase = .playing
        log.info("stream", "playing\(resolution.isEmpty ? "" : " at \(resolution)")")
    }

    func streamFailed(message: String) {
        // Once the picture is up, transient page errors are noise.
        guard phase != .playing else { return }
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
