import Foundation
import GameController
import CoreHaptics
import UIKit
import AVFoundation

/// The JavaScript half of rumble, plus the hand-off to native code.
///
/// Xbox Cloud sends FourMotorRumble packets over the WebRTC data channel named
/// "input". The packet layout below matches the one the web client uses.
///
/// There are two ways those packets can reach a controller on iOS, and which
/// one works depends entirely on the hardware:
///
///  * `GCDeviceHaptics` — Apple's own controller haptics. Present for
///    DualSense, DualShock 4 and MFi pads. **Absent on Xbox controllers**,
///    which is why 1.x and early 2.0 detected the pad, reported it happily
///    and then never vibrated: the engine could not be created at all.
///  * The page's own `GamepadHapticActuator` — `playEffect("dual-rumble")`.
///    This runs inside the stream page, where the browser owns the gamepad,
///    and is the only route that can reach an Xbox pad here.
///
/// So the packets are played in the page when an actuator exists, natively
/// when Apple's haptics exist, and as a last resort on the phone itself.
/// Capability is detected at runtime and reported, never assumed.
enum RumbleBridge {
    static let javaScript = #"""
    (function() {
        if (window.__gsRumble) return;
        window.__gsRumble = true;

        var hooked = typeof WeakSet !== "undefined" ? new WeakSet() : null;
        // Set from native: "page" plays through the gamepad actuator here,
        // "native" only forwards packets, "off" does neither.
        window.__gsRumbleMode = window.__gsRumbleMode || "page";
        window.__gsRumbleScale = window.__gsRumbleScale || 1;

        function post(payload) {
            try {
                window.webkit.messageHandlers.gamestream.postMessage(payload);
            } catch (e) {}
        }

        function actuatorGamepad() {
            var pads = navigator.getGamepads ? navigator.getGamepads() : [];
            for (var i = 0; i < pads.length; i++) {
                var pad = pads[i];
                if (pad && pad.connected && pad.vibrationActuator) return pad;
            }
            return null;
        }

        /// Tell the app what this page can actually do, so Settings can say
        /// so instead of implying rumble works when it cannot.
        var reported = "";
        function reportCapability() {
            var pads = navigator.getGamepads ? navigator.getGamepads() : [];
            var names = [];
            var actuator = false;
            for (var i = 0; i < pads.length; i++) {
                if (!pads[i] || !pads[i].connected) continue;
                names.push(String(pads[i].id).slice(0, 48));
                if (pads[i].vibrationActuator) actuator = true;
            }
            var summary = actuator + "|" + names.join(",");
            if (summary === reported) return;
            reported = summary;
            post({ type: "rumbleCaps", actuator: actuator, gamepads: names.join(", ") });
        }

        window.addEventListener("gamepadconnected", reportCapability);
        window.addEventListener("gamepaddisconnected", reportCapability);
        setInterval(reportCapability, 4000);
        reportCapability();

        function playInPage(data) {
            if (window.__gsRumbleMode !== "page") return false;
            var pad = actuatorGamepad();
            if (!pad) return false;

            var scale = Number(window.__gsRumbleScale) || 1;
            function level(value) {
                var raw = Number(value) || 0;
                if (raw > 1) raw = raw / 100;
                return Math.max(0, Math.min(1, raw * scale));
            }

            var strong = Math.max(level(data.leftMotorPercent),
                                  level(data.leftTriggerMotorPercent));
            var weak = Math.max(level(data.rightMotorPercent),
                                level(data.rightTriggerMotorPercent));
            var duration = Number(data.durationMs) || 0;
            // A zero duration means "until further notice". Keep the effect
            // short and let the next packet renew it, so a dropped session
            // cannot leave the motors running.
            if (duration <= 0) duration = 250;
            duration = Math.max(20, Math.min(duration, 1000));

            try {
                if (strong <= 0.001 && weak <= 0.001) {
                    pad.vibrationActuator.reset && pad.vibrationActuator.reset();
                    return true;
                }
                pad.vibrationActuator.playEffect("dual-rumble", {
                    startDelay: 0,
                    duration: duration,
                    strongMagnitude: strong,
                    weakMagnitude: weak
                });
                return true;
            } catch (e) {
                post({ type: "rumbleCaps", actuator: false, gamepads: "playEffect failed: " + e });
                return false;
            }
        }

        function send(data) {
            post({
                type: "rumble",
                left: Number(data.leftMotorPercent) || 0,
                right: Number(data.rightMotorPercent) || 0,
                leftTrigger: Number(data.leftTriggerMotorPercent) || 0,
                rightTrigger: Number(data.rightTriggerMotorPercent) || 0,
                durationMs: Number(data.durationMs) || 0
            });
        }

        function deliver(data) {
            // Playing in the page is preferred when possible: it is the only
            // path that reaches an Xbox pad, and it skips a round trip.
            var played = playInPage(data);
            if (!played) send(data);
        }

        function parse(buffer) {
            try {
                if (!(buffer instanceof ArrayBuffer)) return;
                var view = new DataView(buffer);
                var offset = 0;

                var messageType;
                if (view.byteLength === 13) {
                    messageType = view.getUint16(offset, true);
                    offset += 2;
                } else {
                    messageType = view.getUint8(offset);
                    offset += 1;
                }
                if (!(messageType & 128)) return;

                if (offset >= view.byteLength) return;
                if (view.getUint8(offset) !== 0) return;   // vibration type
                offset += 1;

                var fields = [
                    ["gamepadIndex", 1], ["leftMotorPercent", 1],
                    ["rightMotorPercent", 1], ["leftTriggerMotorPercent", 1],
                    ["rightTriggerMotorPercent", 1], ["durationMs", 2]
                ];
                var data = {};
                for (var i = 0; i < fields.length; i++) {
                    var width = fields[i][1];
                    if (offset + width > view.byteLength) return;
                    data[fields[i][0]] = width === 2
                        ? view.getUint16(offset, true)
                        : view.getUint8(offset);
                    offset += width;
                }
                deliver(data);
            } catch (e) {}
        }

        function onMessage(event) {
            try {
                if (!event) return;
                if (event.data instanceof ArrayBuffer) {
                    parse(event.data);
                } else if (typeof Blob !== "undefined" && event.data instanceof Blob) {
                    event.data.arrayBuffer().then(parse).catch(function() {});
                }
            } catch (e) {}
        }

        function hook(channel) {
            try {
                if (!channel || (hooked && hooked.has(channel))) return;
                if (channel.label !== "input") return;
                hooked && hooked.add(channel);
                channel.addEventListener("message", onMessage);
            } catch (e) {}
        }

        // The rumble packets arrive on a data channel the page creates, so
        // createDataChannel has to be wrapped before the session opens.
        var Native = window.RTCPeerConnection;
        if (Native && Native.prototype && Native.prototype.createDataChannel) {
            var original = Native.prototype.createDataChannel;
            Native.prototype.createDataChannel = function() {
                var channel = original.apply(this, arguments);
                hook(channel);
                return channel;
            };
        }
        if (Native && Native.prototype) {
            var originalSetRemote = Native.prototype.setRemoteDescription;
            Native.prototype.setRemoteDescription = function() {
                try {
                    this.addEventListener("datachannel", function(event) {
                        hook(event.channel);
                    });
                } catch (e) {}
                return originalSetRemote.apply(this, arguments);
            };
        }

        /// Used by the Settings test button while a stream is on screen.
        window.__gsRumbleTest = function(strong, weak, duration) {
            return playInPage({
                leftMotorPercent: strong,
                rightMotorPercent: weak,
                leftTriggerMotorPercent: 0,
                rightTriggerMotorPercent: 0,
                durationMs: duration
            });
        };
    })();
    """#

    /// Forwarded packets, for the paths the page cannot play itself.
    @MainActor
    static func handle(payload: [String: Any]) {
        func number(_ key: String) -> Float {
            if let value = payload[key] as? Double { return Float(value) }
            if let value = payload[key] as? Int { return Float(value) }
            return 0
        }
        ControllerRumble.shared.play(
            left: number("left"),
            right: number("right"),
            leftTrigger: number("leftTrigger"),
            rightTrigger: number("rightTrigger"),
            durationMs: Double(number("durationMs"))
        )
    }

    @MainActor
    static func handleCapabilities(payload: [String: Any]) {
        ControllerRumble.shared.notePageCapability(
            actuator: payload["actuator"] as? Bool ?? false,
            detail: payload["gamepads"] as? String ?? ""
        )
    }
}

/// Plays rumble on whichever route this hardware actually supports.
@MainActor
final class ControllerRumble: ObservableObject {
    static let shared = ControllerRumble()

    /// Where rumble is coming from. Shown in Settings, because "rumble is on"
    /// is not useful when the hardware cannot do it.
    enum Path: String {
        case controller     // Apple's controller haptics
        case page           // the stream page's gamepad actuator
        case device         // the phone's haptic engine
        case taptics        // UIFeedbackGenerator, which needs no engine
        case unavailable

        var title: String {
            switch self {
            case .controller: return "Controller haptics"
            case .page: return "Controller, through the stream"
            case .device: return "Phone vibration"
            case .taptics: return "Phone taptics"
            case .unavailable: return "Unavailable"
            }
        }
    }

    @Published private(set) var controllerName: String?
    /// True only when Apple's own controller haptics exist for this pad.
    @Published private(set) var supportsHaptics = false
    @Published private(set) var pageActuator = false
    @Published private(set) var pageDetail = ""
    @Published private(set) var path: Path = .unavailable

    private enum EngineKind: Equatable {
        case controller(ObjectIdentifier)
        case device
    }

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var engineKind: EngineKind?
    private var isPlaying = false
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var warnedUnavailable = false
    /// A failed route is retried, never written off.
    ///
    /// The engine for an Xbox pad can fail with "couldn't communicate with a
    /// helper application" and then start working later in the same session —
    /// the haptic server is not always up when the first packet arrives.
    /// Earlier builds disabled the controller route permanently on the first
    /// failure, which meant one unlucky packet cost rumble for good. These
    /// hold a short backoff instead.
    private var controllerRetryAfter = Date.distantPast
    private var deviceRetryAfter = Date.distantPast
    /// Kept for Settings, so a failing route can say what it failed with.
    private(set) var lastEngineError: String?
    private var localityAttempts: [String] = []
    /// Which of the pad's claimed localities to try next. A locality
    /// whose engine is created but cannot play is not the right one.
    private var localityIndex = 0
    private var currentLocality: String?
    private var audioSessionReady = false

    private var stopTimer: Task<Void, Never>?
    private var stopDeadline: Date?
    private var tapticTask: Task<Void, Never>?
    private var tapticGenerator: UIImpactFeedbackGenerator?
    private var tapticStyle: UIImpactFeedbackGenerator.FeedbackStyle?

    private let log = AppLog.shared
    private static let loopDuration: TimeInterval = 1

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect,
                                            object: nil, queue: .main) { _ in
            Task { @MainActor in ControllerRumble.shared.refreshController(reason: "connect") }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect,
                                            object: nil, queue: .main) { _ in
            Task { @MainActor in ControllerRumble.shared.refreshController(reason: "disconnect") }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { _ in
            // The haptic server is not always reachable while the app is
            // coming back to the foreground, so every route gets a clean try.
            Task { @MainActor in ControllerRumble.shared.retryAllRoutes(reason: "app active") }
        })
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        refreshController(reason: "start")
    }

    /// The page reporting what it can do with the gamepad it can see.
    func notePageCapability(actuator: Bool, detail: String) {
        let changed = actuator != pageActuator || detail != pageDetail
        pageActuator = actuator
        pageDetail = detail
        if changed {
            log.info("rumble", "page reports actuator \(actuator ? "available" : "missing")"
                     + (detail.isEmpty ? "" : " for \(detail)"))
            updatePath(reason: "page report")
        }
    }

    // MARK: - Playing

    @discardableResult
    func play(left: Float, right: Float, leftTrigger: Float = 0,
              rightTrigger: Float = 0, durationMs: Double, force: Bool = false) -> Bool {
        guard force || AppSettings.shared.rumbleEnabled else { return false }

        let magnitudeLeft = scale(max(normalise(left), normalise(leftTrigger)))
        let magnitudeRight = scale(max(normalise(right), normalise(rightTrigger)))
        let intensity = min(max(magnitudeRight * 0.78 + magnitudeLeft * 0.48, 0), 1)

        guard intensity > 0.001 else {
            stop()
            return false
        }

        let sharpness = min(max(magnitudeLeft * 0.75 + magnitudeRight * 0.25, 0), 1) * 2 - 1

        // Every usable route in order, so a route that fails this packet costs
        // one silent packet rather than the rest of the session.
        for route in playableRoutes() {
            if route == .taptics {
                playTaptics(intensity: intensity, durationMs: durationMs)
                return true
            }
            guard let kind = engineKind(for: route) else { continue }
            guard prepareEngine(kind) else { continue }
            guard apply(intensity: intensity, sharpness: sharpness) else { continue }

            // A zero duration means "until further notice"; clamp anything
            // longer than a couple of seconds so a lost packet cannot strand
            // the motors.
            let seconds = durationMs > 0 ? min(durationMs / 1000, 2.5) : 2.5
            stopDeadline = Date().addingTimeInterval(seconds)
            startStopTimer()
            return true
        }

        if !warnedUnavailable {
            warnedUnavailable = true
            log.warn("rumble", "nothing can play rumble: \(diagnosis)")
        }
        return false
    }

    func stop() {
        stopTimer?.cancel()
        stopTimer = nil
        stopDeadline = nil
        tapticTask?.cancel()
        tapticTask = nil
        guard isPlaying else { return }
        try? player?.stop(atTime: CHHapticTimeImmediate)
        isPlaying = false
    }

    func teardown() {
        stop()
        engine?.stop(completionHandler: nil)
        engine = nil
        player = nil
        engineKind = nil
    }

    /// Settings' test button. Uses whichever route is live, and says what it
    /// did, so a silent controller is explained rather than mysterious.
    func test() {
        if path == .page, XboxWebView.Registry.shared.streamView != nil {
            let scaleValue = AppSettings.shared.rumbleIntensity
            XboxWebView.Registry.shared.run(
                "window.__gsRumbleScale = \(scaleValue);"
                + "window.__gsRumbleTest && window.__gsRumbleTest(90, 90, 500);"
            )
            log.info("rumble", "test sent to the stream page")
            return
        }

        let route = path
        let played = play(left: 0.9, right: 0.9, durationMs: 600, force: true)
        if played {
            log.info("rumble", "test played through \(path.title.lowercased())")
        } else {
            log.warn("rumble", "test produced nothing via \(route.rawValue): \(diagnosis)")
        }
    }

    /// Plain-language reason there is or is not rumble, for Settings.
    var diagnosis: String {
        if supportsHaptics {
            if Date() < controllerRetryAfter {
                return "this controller's haptic engine would not play"
                    + (lastEngineError.map { " (\($0))" } ?? "")
                    + "; the remaining localities are being tried"
            }
            return "controller haptics are available"
        }
        if pageActuator { return "the stream page can vibrate the controller" }
        if path == .taptics {
            return "this controller does not expose haptics to iOS, so the phone taps instead"
        }

        var reasons: [String] = []
        if controllerName == nil {
            reasons.append("no controller is connected")
        } else {
            reasons.append("this controller does not expose haptics to iOS")
            reasons.append("the stream page reports no vibration actuator")
        }
        if !Self.deviceHapticsSupported {
            reasons.append("this device has no haptic engine")
        } else if !AppSettings.shared.phoneRumbleFallback {
            reasons.append("phone vibration is switched off")
        }
        return reasons.joined(separator: "; ")
    }

    /// Everything known about this controller, for the Settings report. Worth
    /// having verbatim: what a pad claims and what the engine then does are
    /// different facts, and only the pair of them explains a silent session.
    var report: String {
        let controller = activeController()
        var lines: [String] = []
        lines.append("Rumble route: \(path.title)")
        lines.append("Controller: \(controller?.vendorName ?? "none")")
        if let controller {
            lines.append("Category: \(controller.productCategory)")
            lines.append("Attached to device: \(controller.isAttachedToDevice)")
            if let haptics = controller.haptics {
                let claimed = haptics.supportedLocalities.map(\.rawValue).sorted()
                lines.append("Claimed localities: \(claimed.isEmpty ? "none" : claimed.joined(separator: ", "))")
            } else {
                lines.append("Claimed localities: no GCDeviceHaptics")
            }
        }
        lines.append("Locality in use: \(currentLocality ?? "none")")
        lines.append("Engine attempts: \(localityAttempts.isEmpty ? "none yet" : localityAttempts.joined(separator: " | "))")
        lines.append("Last engine error: \(lastEngineError ?? "none")")
        lines.append("Device haptic engine: \(Self.deviceHapticsSupported ? "supported" : "unsupported")")
        lines.append("Stream page actuator: \(pageActuator ? "yes" : "no")")
        if !pageDetail.isEmpty { lines.append("Page gamepads: \(pageDetail)") }
        lines.append("Phone fallback: \(AppSettings.shared.phoneRumbleFallback ? "on" : "off")")
        return lines.joined(separator: "\n")
    }

    // MARK: - Routing

    private static var deviceHapticsSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private static var tapticsAvailable: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// The routes that could carry this packet, best first.
    private func playableRoutes() -> [Path] {
        var routes: [Path] = []
        let now = Date()
        if supportsHaptics, now >= controllerRetryAfter { routes.append(.controller) }
        if Self.deviceHapticsSupported, now >= deviceRetryAfter,
           AppSettings.shared.phoneRumbleFallback { routes.append(.device) }
        if Self.tapticsAvailable, AppSettings.shared.phoneRumbleFallback { routes.append(.taptics) }
        return routes
    }

    /// What Settings shows. Backoffs are deliberately ignored here: a route
    /// that is being retried is still the route, and saying "Unavailable" for
    /// a few seconds would be a lie in the other direction.
    private func updatePath(reason: String) {
        let next: Path
        if supportsHaptics {
            next = .controller
        } else if pageActuator {
            next = .page
        } else if Self.deviceHapticsSupported, AppSettings.shared.phoneRumbleFallback {
            next = .device
        } else if Self.tapticsAvailable, AppSettings.shared.phoneRumbleFallback {
            next = .taptics
        } else {
            next = .unavailable
        }
        guard next != path else { return }
        path = next
        warnedUnavailable = false
        // A route change means the old engine belongs to the wrong target.
        teardown()
        log.info("rumble", "path is now \(next.rawValue) (\(reason))")
    }

    /// Recomputed when the phone-vibration preference changes.
    func settingsChanged() {
        updatePath(reason: "settings")
    }

    /// Clears the backoffs, so a route that failed earlier gets a clean try.
    func retryAllRoutes(reason: String) {
        controllerRetryAfter = .distantPast
        deviceRetryAfter = .distantPast
        localityIndex = 0
        log.debug("rumble", "routes re-armed (\(reason))")
        updatePath(reason: reason)
    }

    private func engineKind(for route: Path) -> EngineKind? {
        switch route {
        case .controller:
            guard let controller = activeController(), controller.haptics != nil else { return nil }
            return .controller(ObjectIdentifier(controller))
        case .device:
            return .device
        case .page, .taptics, .unavailable:
            return nil
        }
    }

    private func refreshController(reason: String) {
        let controller = activeController()
        let changed = controller?.vendorName != controllerName
        controllerName = controller?.vendorName
        supportsHaptics = controller?.haptics != nil
        if changed { retryAllRoutes(reason: "controller changed") }
        log.info("rumble", "\(reason): \(controllerName ?? "no controller")"
                 + (supportsHaptics
                    ? " with Apple haptics"
                    : " without Apple haptics (normal for Xbox pads)"))
        if controller == nil { teardown() }
        updatePath(reason: reason)
    }

    private func activeController() -> GCController? {
        if let current = GCController.current, current.haptics != nil { return current }
        let all = GCController.controllers()
        return all.first { $0.haptics != nil } ?? all.first
    }

    // MARK: - Engine

    private func prepareEngine(_ kind: EngineKind) -> Bool {
        if engineKind == kind, player != nil { return true }
        teardown()

        let created: CHHapticEngine?
        switch kind {
        case .controller:
            created = makeControllerEngine()
        case .device:
            created = try? CHHapticEngine()
        }
        guard let engine = created else {
            noteFailure(kind, reason: lastEngineError ?? "no engine could be created")
            return false
        }

        // Configuration has to happen before the engine runs, and the engine
        // must not be started here. CHHapticEngine starts itself when a player
        // first plays; calling start() by hand is what threw "couldn't
        // communicate with a helper application" on this pad, and treating
        // that throw as "the controller cannot rumble" is what silenced it.
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.stoppedHandler = { _ in
            Task { @MainActor in ControllerRumble.shared.engineDidStop() }
        }
        engine.resetHandler = {
            Task { @MainActor in ControllerRumble.shared.engineDidStop() }
        }

        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0,
                duration: Self.loopDuration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let advanced = try engine.makeAdvancedPlayer(with: pattern)
            advanced.loopEnabled = true
            advanced.loopEnd = Self.loopDuration

            engineKind = kind
            self.engine = engine
            self.player = advanced
            log.info("rumble", "haptic player ready (\(path.rawValue))")
            return true
        } catch {
            log.error("rumble", "haptic setup failed: \(Self.describe(error))")
            engine.stop(completionHandler: nil)
            self.engine = nil
            self.player = nil
            engineKind = nil
            noteFailure(kind, reason: Self.describe(error))
            return false
        }
    }

    /// A route that failed backs off briefly. It is not written off: this pad's
    /// engine can refuse one packet and take the next.
    private func noteFailure(_ kind: EngineKind, reason: String) {
        lastEngineError = reason
        let backoff = Date().addingTimeInterval(4)
        switch kind {
        case .controller:
            let first = controllerRetryAfter == .distantPast
            controllerRetryAfter = backoff
            // The locality that just failed is not the one. Move to the next
            // one the pad claims before retrying, rather than hammering the
            // same dead endpoint for the whole session.
            localityIndex += 1
            if localityIndex >= controllerLocalities().count {
                localityIndex = 0
                controllerRetryAfter = Date().addingTimeInterval(20)
            }
            if first {
                log.warn("rumble", "\(controllerName ?? "this controller") would not play through "
                         + "\(currentLocality ?? "its haptics") (\(reason)); trying the next "
                         + "locality, and another route meanwhile")
            }
        case .device:
            deviceRetryAfter = backoff
            log.warn("rumble", "the phone's haptic engine will not start (\(reason))")
        }
    }

    /// The localities this pad claims, best first.
    private func controllerLocalities() -> [GCHapticsLocality] {
        guard let haptics = activeController()?.haptics else { return [] }
        let claimed = haptics.supportedLocalities
        let order: [GCHapticsLocality] = [.default, .all, .handles, .leftHandle, .rightHandle,
                                          .triggers, .leftTrigger, .rightTrigger]
        let filtered = order.filter { $0 == .default || claimed.contains($0) }
        return filtered.isEmpty ? [.default] : filtered
    }

    /// CoreHaptics talks to a system helper over XPC, and that connection is
    /// tied to the process's audio session. Without an active one the engine
    /// can be created and then fail to play with NSCocoaErrorDomain 4097,
    /// "couldn't communicate with a helper application" — which is exactly
    /// what this pad reports. Activating a session costs nothing and is the
    /// one remaining thing that can change that outcome.
    private func prepareAudioSession() {
        guard !audioSessionReady else { return }
        audioSessionReady = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default,
                                    options: [.mixWithOthers])
            try session.setActive(true, options: [])
            log.debug("rumble", "audio session active for haptics")
        } catch {
            log.debug("rumble", "audio session would not activate: \(Self.describe(error))")
        }
    }

    /// Creates, but does not start, an engine for the controller.
    ///
    /// Nothing here is started: `start()` is the call that throws 4097 on this
    /// hardware, and the player brings the engine up lazily and more
    /// reliably. Each failure advances to the next locality the pad claims,
    /// because an engine that is created is not an engine that can play.
    private func makeControllerEngine() -> CHHapticEngine? {
        guard let haptics = activeController()?.haptics else {
            lastEngineError = "the controller exposes no haptics"
            return nil
        }
        prepareAudioSession()

        let localities = controllerLocalities()
        guard localityIndex < localities.count else {
            localityIndex = 0
            return nil
        }

        for index in localityIndex..<localities.count {
            let locality = localities[index]
            if let engine = haptics.createEngine(withLocality: locality) {
                localityIndex = index
                currentLocality = locality.rawValue
                record("\(locality.rawValue): created")
                log.info("rumble", "engine created on locality \(locality.rawValue)")
                return engine
            }
            record("\(locality.rawValue): nil")
        }
        lastEngineError = "no remaining locality produced an engine"
        return nil
    }

    private func record(_ attempt: String) {
        localityAttempts.removeAll { $0.hasPrefix(attempt.split(separator: ":")[0] + ":") }
        localityAttempts.append(attempt)
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription) [\(nsError.domain) \(nsError.code)]"
    }

    private func engineDidStop() {
        isPlaying = false
        player = nil
        engine = nil
        engineKind = nil
    }

    @discardableResult
    private func apply(intensity: Float, sharpness: Float) -> Bool {
        guard let player else { return false }
        let parameters = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: sharpness, relativeTime: 0)
        ]

        func send(startIfNeeded: Bool) throws {
            if !isPlaying {
                // Start silent, apply the real intensity, then unmute, so the
                // first packet does not arrive as a click at full strength.
                player.isMuted = true
                try player.start(atTime: CHHapticTimeImmediate)
                try player.sendParameters(parameters, atTime: CHHapticTimeImmediate)
                player.isMuted = false
                isPlaying = true
                return
            }
            try player.sendParameters(parameters, atTime: CHHapticTimeImmediate)
        }

        do {
            try send(startIfNeeded: true)
            return true
        } catch {
            // The engine had not come up on its own. Start it explicitly and
            // try the packet once more before giving the route up.
            log.debug("rumble", "playback needs an explicit engine start: \(Self.describe(error))")
            do {
                try engine?.start()
                isPlaying = false
                try send(startIfNeeded: false)
                return true
            } catch {
                log.warn("rumble", "playback failed: \(Self.describe(error))")
                if let locality = currentLocality {
                    record("\(locality): created, then \(Self.describe(error))")
                }
                let kind = engineKind
                engineDidStop()
                if let kind { noteFailure(kind, reason: Self.describe(error)) }
                return false
            }
        }
    }

    /// Taptics have no continuous mode, so a rumble becomes a short train of
    /// impacts. It is not a motor, and it is not pretending to be one, but it
    /// is feedback where CoreHaptics can produce none.
    private func playTaptics(intensity: Float, durationMs: Double) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle =
            intensity > 0.66 ? .heavy : (intensity > 0.33 ? .medium : .light)
        let generator = (tapticStyle == style ? tapticGenerator : nil)
            ?? UIImpactFeedbackGenerator(style: style)
        tapticGenerator = generator
        tapticStyle = style
        generator.prepare()
        generator.impactOccurred(intensity: CGFloat(min(max(intensity, 0.1), 1)))

        let seconds = durationMs > 0 ? min(durationMs / 1000, 2.5) : 0.25
        guard seconds > 0.14 else { return }

        tapticTask?.cancel()
        tapticTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(seconds)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, let self else { return }
                self.tapticGenerator?.impactOccurred(intensity: CGFloat(min(max(intensity, 0.1), 1)))
            }
        }
    }

    private func startStopTimer() {
        guard stopTimer == nil else { return }
        stopTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self else { return }
                guard let deadline = self.stopDeadline else { return }
                if Date() >= deadline {
                    self.stop()
                    return
                }
            }
        }
    }

    private func normalise(_ value: Float) -> Float {
        let scaled = value > 1 ? value / 100 : value
        return min(max(scaled, 0), 1)
    }

    private func scale(_ value: Float) -> Float {
        guard value > 0.005 else { return 0 }
        return min(max(value * AppSettings.shared.rumbleIntensity, 0.05), 1)
    }
}
