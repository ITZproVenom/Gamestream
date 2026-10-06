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
                    // Once per connection. This method is called again on
                    // every renegotiation, and each call used to add another
                    // listener to the same connection.
                    if (!this.__gsDataChannelHooked) {
                        this.__gsDataChannelHooked = true;
                        this.addEventListener("datachannel", function(event) {
                            hook(event.channel);
                        });
                    }
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

/// One haptic engine and whichever way of driving it this hardware accepts.
///
/// Two strategies, because one is not enough. A held continuous pattern is the
/// obvious way to render rumble — it is the only way to change strength
/// smoothly without restarting anything — but it asks the haptic server to
/// keep a long-lived player alive on the device, and that is exactly the
/// request some adapters refuse. When the refusal comes it arrives at play
/// time as an XPC error, long after the engine was created and reported
/// healthy, which is why a failure here has to be survivable rather than
/// fatal.
///
/// So the fallback is not a different device, it is a different way of asking
/// the same device: a train of short transient events, each its own
/// throwaway player, fired on a cadence derived from the magnitude. It is
/// coarser than a continuous pattern and it cannot glide between strengths,
/// but nothing has to stay resident between pulses. If the smooth route is
/// refused, this one is tried on the same engine before the controller is
/// written off and the phone takes over.
@MainActor
private final class HapticPlayback {
    enum Drive { case continuous, pulsed }

    private enum PlaybackError: Error { case noHeldPlayer }

    static let loopDuration: TimeInterval = 1

    let engine: CHHapticEngine
    let owner: ObjectIdentifier?
    private(set) var drive: Drive
    private var held: CHHapticAdvancedPatternPlayer?
    private var pulse: Timer?
    private var target = RumbleProfile(weak: 0, strong: 0)

    var isPlaying = false
    var lastProfile: RumbleProfile?
    var lastUpdateAt: TimeInterval = 0

    /// The engine is brought up here rather than left for the first player to
    /// start lazily. Starting it explicitly means a device that will never
    /// work says so once, at connect time, instead of once per packet.
    init(engine: CHHapticEngine, owner: ObjectIdentifier?) throws {
        self.engine = engine
        self.owner = owner
        self.drive = .continuous
        try engine.start()

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
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = Self.loopDuration
            held = player
        } catch {
            // The engine exists but will not hold a pattern. Pulses might
            // still land, so this is not the end of the controller route.
            drive = .pulsed
        }
    }

    /// Renders a profile. Throws only when neither strategy is left.
    func apply(_ profile: RumbleProfile) throws {
        target = profile
        if drive == .continuous {
            do {
                try applyHeld(profile)
                return
            } catch {
                // Demote once, then let the pulse train answer for this packet
                // instead of losing it.
                held = nil
                drive = .pulsed
                isPlaying = false
            }
        }
        applyPulsed(profile)
    }

    private func applyHeld(_ profile: RumbleProfile) throws {
        guard let held else { throw PlaybackError.noHeldPlayer }
        let parameters = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: profile.intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: profile.sharpness, relativeTime: 0)
        ]
        if isPlaying {
            try held.sendParameters(parameters, atTime: CHHapticTimeImmediate)
            return
        }
        // Started muted so the first packet does not land as a click at full
        // strength, then unmuted once the real intensity is in place.
        held.isMuted = true
        try held.start(atTime: CHHapticTimeImmediate)
        try held.sendParameters(parameters, atTime: CHHapticTimeImmediate)
        held.isMuted = false
        isPlaying = true
    }

    private func applyPulsed(_ profile: RumbleProfile) {
        guard !profile.isSilent else {
            stopPulse()
            return
        }
        isPlaying = true
        let interval = profile.pulseInterval
        // Only rebuild the timer when the cadence has really moved, otherwise
        // a stream of similar packets restarts it several times a second and
        // the train never actually fires.
        if let pulse, abs(pulse.timeInterval - interval) < 0.008 { return }
        stopPulse()
        firePulse()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.firePulse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pulse = timer
    }

    private func firePulse() {
        guard !target.isSilent else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: target.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness,
                                       value: (target.sharpness + 1) / 2)
            ],
            relativeTime: 0
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    private func stopPulse() {
        pulse?.invalidate()
        pulse = nil
    }

    /// What is actually driving the motors, for the diagnostics report.
    var driveDescription: String {
        drive == .continuous ? "continuous" : "pulsed"
    }

    func stopPlayer() {
        stopPulse()
        if isPlaying { try? held?.stop(atTime: CHHapticTimeImmediate) }
        isPlaying = false
        lastProfile = nil
        lastUpdateAt = 0
        target = RumbleProfile(weak: 0, strong: 0)
    }

    func shutdown() {
        stopPlayer()
        held = nil
        engine.stop(completionHandler: nil)
    }
}

/// What the motors should be doing, as two magnitudes.
struct RumbleProfile: Equatable {
    var weak: Float
    var strong: Float

    var isSilent: Bool { weak < 0.01 && strong < 0.01 }

    /// Intensity the player hears, weighted towards the heavy motor.
    var intensity: Float { min(max(strong * 0.78 + weak * 0.48, 0), 1) }
    var sharpness: Float { min(max(weak * 0.75 + strong * 0.25, 0), 1) * 2 - 1 }

    /// How often the pulse train fires when a held pattern is refused.
    /// Stronger rumble reads as faster, because a transient cannot be made
    /// to last longer — only to repeat sooner.
    var pulseInterval: TimeInterval {
        let magnitude = Double(min(max(intensity, 0), 1))
        return 0.115 - 0.070 * magnitude
    }

    /// Small changes are not worth a round trip to the haptic server.
    func materiallyDiffers(from other: RumbleProfile) -> Bool {
        abs(weak - other.weak) > 0.02 || abs(strong - other.strong) > 0.02
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

    enum TestPhase: Equatable {
        case idle
        case waitingForTrigger
        case playing
        case finished(String)
    }

    @Published private(set) var controllerName: String?
    @Published private(set) var supportsHaptics = false
    @Published private(set) var pageActuator = false
    @Published private(set) var pageDetail = ""
    @Published private(set) var path: Path = .unavailable
    @Published private(set) var testPhase: TestPhase = .idle

    // MARK: Playback

    /// One engine per controller, keyed by identity. A pad that reconnects is
    /// a different object and gets a new engine rather than a stale one.
    private var controllerPlayback: [ObjectIdentifier: HapticPlayback] = [:]
    private var phonePlayback: HapticPlayback?

    /// Parameters are not resent faster than this. A stream can deliver
    /// rumble packets far more often than the hardware can act on them, and
    /// the surplus only adds latency to the ones that matter.
    private static let updateInterval: TimeInterval = 0.035

    private var controllerRetryAfter: Date = .distantPast
    private var phoneRetryAfter: Date = .distantPast
    private var stopTimer: Task<Void, Never>?
    private var stopDeadline: Date?

    // MARK: Taptics

    private var tapticTask: Task<Void, Never>?
    private var tapticGenerator: UIImpactFeedbackGenerator?
    private var tapticStyle: UIImpactFeedbackGenerator.FeedbackStyle?

    // MARK: Diagnostics

    private(set) var lastEngineError: String?
    private var localityAttempts: [String] = []
    private var localityIndex = 0
    private var currentLocality: String?
    private var audioSessionReady = false
    private var preferredController: GCController?

    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var warnedUnavailable = false
    private var testTimeout: Task<Void, Never>?
    private var testRun: Task<Void, Never>?

    private let log = AppLog.shared

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
            Task { @MainActor in ControllerRumble.shared.retryAllRoutes(reason: "app active") }
        })
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        refreshController(reason: "start")
    }

    func notePageCapability(actuator: Bool, detail: String) {
        let changed = actuator != pageActuator || detail != pageDetail
        pageActuator = actuator
        pageDetail = detail
        guard changed else { return }
        log.info("rumble", "page reports actuator \(actuator ? "available" : "missing")"
                 + (detail.isEmpty ? "" : " for \(detail)"))
        updatePath(reason: "page report")
    }

    // MARK: - Playing

    @discardableResult
    func play(left: Float, right: Float, leftTrigger: Float = 0,
              rightTrigger: Float = 0, durationMs: Double, force: Bool = false) -> Bool {
        guard force || AppSettings.shared.rumbleEnabled else { return false }

        let scale = AppSettings.shared.rumbleIntensity
        func level(_ value: Float) -> Float {
            let normalised = value > 1 ? value / 100 : value
            return min(max(normalised * scale, 0), 1)
        }

        let profile = RumbleProfile(
            weak: max(level(right), level(rightTrigger)),
            strong: max(level(left), level(leftTrigger))
        )

        guard !profile.isSilent else {
            stop()
            return false
        }

        // Every route is tried on every packet. A route that failed a moment
        // ago is not written off; it is simply not first in line until its
        // backoff expires.
        if playOnController(profile) || playOnPhone(profile) {
            let seconds = durationMs > 0 ? min(durationMs / 1000, 2.5) : 2.5
            stopDeadline = Date().addingTimeInterval(seconds)
            startStopTimer()
            return true
        }
        if playTaptics(profile, durationMs: durationMs) { return true }

        if !warnedUnavailable {
            warnedUnavailable = true
            log.warn("rumble", "nothing can play rumble: \(diagnosis)")
        }
        return false
    }

    /// Tries the controller, walking to the next locality on each failure.
    ///
    /// One attempt per packet was not a sweep: the first failure started a
    /// four-second backoff, and every later shot in a burst was skipped
    /// before it could reach the next locality. Five claimed localities were
    /// reported and exactly one was ever tried.
    private func playOnController(_ profile: RumbleProfile) -> Bool {
        guard Date() >= controllerRetryAfter else { return false }
        let localities = controllerLocalities()
        for _ in 0..<localities.count {
            switch attemptController(profile) {
            case .played: return true
            case .unavailable: return false
            case .failed: continue
            }
        }
        return false
    }

    private enum Attempt { case played, failed, unavailable }

    private func attemptController(_ profile: RumbleProfile) -> Attempt {
        guard let controller = activeController(), controller.haptics != nil else {
            return .unavailable
        }
        let identity = ObjectIdentifier(controller)

        do {
            let playback: HapticPlayback
            if let existing = controllerPlayback[identity] {
                playback = existing
            } else {
                shutdownController(identity)
                guard let engine = makeControllerEngine(for: controller) else {
                    throw RumbleFailure.noEngine(lastEngineError ?? "no engine could be created")
                }
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = false
                let created = try HapticPlayback(engine: engine, owner: identity)
                install(created, for: identity)
                controllerPlayback[identity] = created
                playback = created
            }
            try update(playback, with: profile)
            // A working controller means the phone does not need to step in.
            phoneRetryAfter = .distantPast
            return .played
        } catch {
            shutdownController(identity)
            note(failure: error, route: .controller)
            return .failed
        }
    }

    private func playOnPhone(_ profile: RumbleProfile) -> Bool {
        guard AppSettings.shared.phoneRumbleFallback else { return false }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        guard Date() >= phoneRetryAfter else { return false }

        do {
            let playback: HapticPlayback
            if let existing = phonePlayback {
                playback = existing
            } else {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = false
                let created = try HapticPlayback(engine: engine, owner: nil)
                install(created, for: nil)
                phonePlayback = created
                playback = created
            }
            try update(playback, with: profile)
            return true
        } catch {
            phonePlayback?.shutdown()
            phonePlayback = nil
            note(failure: error, route: .device)
            return false
        }
    }

    /// Pushes a profile into a live playback, throttled.
    ///
    /// The throttle is here rather than in the playback because it is about
    /// how often we are willing to talk to the haptic server at all, not
    /// about which strategy is answering.
    private func update(_ playback: HapticPlayback, with profile: RumbleProfile) throws {
        let now = Date().timeIntervalSinceReferenceDate
        if let last = playback.lastProfile,
           now - playback.lastUpdateAt < Self.updateInterval,
           !profile.materiallyDiffers(from: last) {
            return
        }
        playback.lastProfile = profile
        playback.lastUpdateAt = now
        try playback.apply(profile)
    }

    /// An engine that stops or resets is discarded, so the next packet builds
    /// a fresh one rather than talking to something that is no longer there.
    private func install(_ playback: HapticPlayback, for identity: ObjectIdentifier?) {
        playback.engine.stoppedHandler = { _ in
            Task { @MainActor in ControllerRumble.shared.discard(identity) }
        }
        playback.engine.resetHandler = {
            Task { @MainActor in ControllerRumble.shared.discard(identity) }
        }
    }

    private func discard(_ identity: ObjectIdentifier?) {
        if let identity {
            controllerPlayback.removeValue(forKey: identity)?.stopPlayer()
        } else {
            phonePlayback?.stopPlayer()
            phonePlayback = nil
        }
    }

    private func shutdownController(_ identity: ObjectIdentifier) {
        controllerPlayback.removeValue(forKey: identity)?.shutdown()
    }

    private enum RumbleFailure: Error, LocalizedError {
        case noEngine(String)
        var errorDescription: String? {
            switch self { case .noEngine(let reason): return reason }
        }
    }

    private func note(failure: Error, route: Path) {
        let reason = Self.describe(failure)
        lastEngineError = reason
        if let locality = currentLocality, route == .controller {
            record("\(locality): created, then \(reason)")
        }
        switch route {
        case .controller:
            log.warn("rumble", "\(currentLocality ?? "this controller") would not play: \(reason)")
            localityIndex += 1
            // Backoff only once the whole claimed set has been exhausted;
            // otherwise the next locality never gets its turn.
            if localityIndex >= controllerLocalities().count {
                localityIndex = 0
                controllerRetryAfter = Date().addingTimeInterval(20)
                log.warn("rumble", "every locality this controller claims refused to play")
            }
        default:
            phoneRetryAfter = Date().addingTimeInterval(5)
            log.warn("rumble", "the phone's haptic engine will not play (\(reason))")
        }
    }

    // MARK: - Taptics

    /// No engine, no server, no XPC. This is feedback when CoreHaptics can
    /// produce none, and it is the phone rather than the pad.
    @discardableResult
    private func playTaptics(_ profile: RumbleProfile, durationMs: Double) -> Bool {
        guard AppSettings.shared.phoneRumbleFallback,
              UIDevice.current.userInterfaceIdiom == .phone else { return false }

        let intensity = profile.intensity
        let style: UIImpactFeedbackGenerator.FeedbackStyle =
            intensity > 0.66 ? .heavy : (intensity > 0.33 ? .medium : .light)
        let generator = (tapticStyle == style ? tapticGenerator : nil)
            ?? UIImpactFeedbackGenerator(style: style)
        tapticGenerator = generator
        tapticStyle = style
        generator.prepare()
        generator.impactOccurred(intensity: CGFloat(min(max(intensity, 0.1), 1)))

        let seconds = durationMs > 0 ? min(durationMs / 1000, 2.5) : 0.25
        guard seconds > 0.14 else { return true }

        tapticTask?.cancel()
        tapticTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(seconds)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, let self else { return }
                self.tapticGenerator?.impactOccurred(
                    intensity: CGFloat(min(max(intensity, 0.1), 1)))
            }
        }
        return true
    }

    // MARK: - Stopping

    func stop() {
        stopTimer?.cancel()
        stopTimer = nil
        stopDeadline = nil
        tapticTask?.cancel()
        tapticTask = nil
        for playback in controllerPlayback.values { playback.stopPlayer() }
        phonePlayback?.stopPlayer()
    }

    func teardown() {
        stop()
        for playback in controllerPlayback.values { playback.shutdown() }
        controllerPlayback.removeAll()
        phonePlayback?.shutdown()
        phonePlayback = nil
    }

    private func startStopTimer() {
        guard stopTimer == nil else { return }
        stopTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self, let deadline = self.stopDeadline else { return }
                if Date() >= deadline {
                    self.stop()
                    return
                }
            }
        }
    }

    // MARK: - Engines

    private func controllerLocalities() -> [GCHapticsLocality] {
        guard let haptics = activeController()?.haptics else { return [.default] }
        let claimed = haptics.supportedLocalities
        let order: [GCHapticsLocality] = [.default, .all, .handles, .leftHandle, .rightHandle,
                                          .triggers, .leftTrigger, .rightTrigger]
        let filtered = order.filter { $0 == .default || claimed.contains($0) }
        return filtered.isEmpty ? [.default] : filtered
    }

    /// CoreHaptics reaches a system helper over XPC, and that connection is
    /// tied to the process audio session. Without an active one the engine can
    /// be created and then fail to play with NSCocoaErrorDomain 4097.
    private func prepareAudioSession() {
        guard !audioSessionReady else { return }
        audioSessionReady = true
        do {
            let session = AVAudioSession.sharedInstance()
            // Not mixable. A mixing session is a secondary audio client, and
            // the haptic server treats it as lower priority than one that owns
            // playback outright; .moviePlayback is what a full-screen video
            // client asks for and is the closest match to what a stream is.
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
            log.debug("rumble", "audio session active for haptics")
        } catch {
            log.debug("rumble", "audio session would not activate: \(Self.describe(error))")
        }
    }

    /// Created but never started. `start()` is the call that throws on this
    /// hardware, and the player brings the engine up lazily instead.
    private func makeControllerEngine(for controller: GCController) -> CHHapticEngine? {
        guard let haptics = controller.haptics else {
            lastEngineError = "the controller exposes no haptics"
            return nil
        }
        prepareAudioSession()

        let localities = controllerLocalities()
        log.info("rumble", "localities claimed: "
                 + localities.map(\.rawValue).joined(separator: ", "))

        for index in min(localityIndex, localities.count - 1)..<localities.count {
            let locality = localities[index]
            if let engine = haptics.createEngine(withLocality: locality) {
                localityIndex = index
                currentLocality = locality.rawValue
                record("\(locality.rawValue): created")
                return engine
            }
            record("\(locality.rawValue): nil")
        }
        lastEngineError = "no remaining locality produced an engine"
        return nil
    }

    private func record(_ attempt: String) {
        let prefix = attempt.split(separator: ":").first.map(String.init) ?? attempt
        localityAttempts.removeAll { $0.hasPrefix(prefix + ":") }
        localityAttempts.append(attempt)
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription) [\(nsError.domain) \(nsError.code)]"
    }

    // MARK: - Routing

    private static var deviceHapticsSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private func updatePath(reason: String) {
        let next: Path
        if supportsHaptics {
            next = .controller
        } else if pageActuator {
            next = .page
        } else if Self.deviceHapticsSupported, AppSettings.shared.phoneRumbleFallback {
            next = .device
        } else if UIDevice.current.userInterfaceIdiom == .phone,
                  AppSettings.shared.phoneRumbleFallback {
            next = .taptics
        } else {
            next = .unavailable
        }
        guard next != path else { return }
        path = next
        warnedUnavailable = false
        teardown()
        log.info("rumble", "path is now \(next.rawValue) (\(reason))")
    }

    func settingsChanged() { updatePath(reason: "settings") }

    func retryAllRoutes(reason: String) {
        controllerRetryAfter = .distantPast
        phoneRetryAfter = .distantPast
        localityIndex = 0
        log.debug("rumble", "routes re-armed (\(reason))")
        updatePath(reason: reason)
    }

    private func refreshController(reason: String) {
        let controller = activeController()
        let changed = controller?.vendorName != controllerName
        controllerName = controller?.vendorName
        supportsHaptics = controller?.haptics != nil
        if changed { retryAllRoutes(reason: "controller changed") }
        log.info("rumble", "\(reason): \(controllerName ?? "no controller")"
                 + (supportsHaptics ? " with haptics" : " without haptics"))
        if controller == nil { teardown() }
        updatePath(reason: reason)
    }

    private func activeController() -> GCController? {
        if let preferred = preferredController,
           GCController.controllers().contains(where: { $0 === preferred }) {
            return preferred
        }
        if let current = GCController.current, current.haptics != nil { return current }
        let all = GCController.controllers()
        return all.first { $0.haptics != nil } ?? all.first
    }

    // MARK: - Guided test

    /// Ask for a real trigger pull, then fire a burst.
    ///
    /// Waiting for input names the pad being held rather than guessing from
    /// `GCController.current`, and guarantees the controller is awake and
    /// delivering input to this app before an engine is requested.
    func beginGuidedTest() {
        cancelTest()
        retryAllRoutes(reason: "guided test")
        testPhase = .waitingForTrigger
        log.info("rumble", "guided test: waiting for a trigger pull")

        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in
                guard let self else { return }
                guard pad.rightTrigger.value > 0.4 || pad.leftTrigger.value > 0.4 else { return }
                Task { @MainActor in self.triggerPulled(on: pad.controller) }
            }
        }

        testTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.testPhase == .waitingForTrigger else { return }
                self?.finishTest("No trigger was pressed. Is the controller connected to this app?")
            }
        }
    }

    func cancelTest() {
        testTimeout?.cancel()
        testTimeout = nil
        testRun?.cancel()
        testRun = nil
        clearTestHandlers()
        stop()
        if case .finished = testPhase {} else { testPhase = .idle }
    }

    private func clearTestHandlers() {
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
    }

    private func triggerPulled(on controller: GCController?) {
        guard testPhase == .waitingForTrigger else { return }
        testTimeout?.cancel()
        testTimeout = nil
        testPhase = .playing

        if let controller {
            preferredController = controller
            controllerName = controller.vendorName
            supportsHaptics = controller.haptics != nil
            log.info("rumble", "trigger pulled on \(controller.vendorName ?? "a controller")"
                     + " (\(controller.haptics != nil ? "reports haptics" : "no haptics"))")
            updatePath(reason: "trigger pulled")
        }

        testRun = Task { [weak self] in await self?.fireBurst() }
    }

    /// Tries every claimed locality once and records what each one did.
    ///
    /// Reporting five localities while testing one was worse than useless:
    /// it looked like a sweep and was not. This is the sweep.
    private func sweepLocalities() {
        guard let controller = activeController(), controller.haptics != nil else { return }
        let localities = controllerLocalities()
        controllerRetryAfter = .distantPast
        localityIndex = 0
        let probe = RumbleProfile(weak: 0.6, strong: 0.9)

        for index in 0..<localities.count {
            localityIndex = index
            let identity = ObjectIdentifier(controller)
            shutdownController(identity)
            if attemptController(probe) == .played {
                record("\(localities[index].rawValue): PLAYS")
                log.info("rumble", "locality \(localities[index].rawValue) plays")
                stop()
                return
            }
            stop()
        }
        localityIndex = 0
    }

    /// Six shots and a recoil, which is unmistakable if it plays at all.
    private func fireBurst() async {
        sweepLocalities()

        var played = 0
        for shot in 0..<6 {
            let heavy = shot == 5
            if play(left: heavy ? 1 : 0.85, right: heavy ? 0.9 : 0.5,
                    durationMs: heavy ? 260 : 80, force: true) {
                played += 1
            }
            try? await Task.sleep(for: .milliseconds(heavy ? 300 : 120))
            stop()
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(heavy ? 0 : 45))
        }
        clearTestHandlers()

        if played == 0 {
            finishTest("Nothing played: \(diagnosis).")
        } else {
            let route = path == .controller
                ? "the controller" + (currentLocality.map { " (\($0))" } ?? "")
                : path.title.lowercased()
            finishTest("Fired six shots through \(route). If you felt nothing, "
                       + "this route reports success but produces no motion.")
        }
    }

    private func finishTest(_ message: String) {
        testPhase = .finished(message)
        log.info("rumble", "guided test: \(message)")
    }

    // MARK: - Reporting

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
                lines.append("Claimed localities: "
                             + (claimed.isEmpty ? "none" : claimed.joined(separator: ", ")))
            } else {
                lines.append("Claimed localities: no GCDeviceHaptics")
            }
        }
        lines.append("Locality in use: \(currentLocality ?? "none")")
        if let identity = controller.map(ObjectIdentifier.init),
           let playback = controllerPlayback[identity] {
            lines.append("Drive strategy: \(playback.driveDescription)")
        } else {
            lines.append("Drive strategy: not started")
        }
        lines.append("Engine attempts: "
                     + (localityAttempts.isEmpty ? "none yet"
                        : localityAttempts.joined(separator: " | ")))
        lines.append("Last engine error: \(lastEngineError ?? "none")")
        lines.append("Device haptic engine: "
                     + (Self.deviceHapticsSupported ? "supported" : "unsupported"))
        lines.append("Stream page actuator: \(pageActuator ? "yes" : "no")")
        if !pageDetail.isEmpty { lines.append("Page gamepads: \(pageDetail)") }
        lines.append("Phone fallback: \(AppSettings.shared.phoneRumbleFallback ? "on" : "off")")
        lines.append("Player page alive: "
                     + (XboxWebView.Registry.shared.streamView == nil ? "no" : "yes"))
        return lines.joined(separator: "\n")
    }
}
