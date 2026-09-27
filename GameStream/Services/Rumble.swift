import Foundation
import GameController
import CoreHaptics

/// The JavaScript half of controller rumble, plus the hand-off to native code.
///
/// Xbox Cloud sends FourMotorRumble packets over the WebRTC data channel named
/// "input". The packet layout below matches Better xCloud's parser.
enum RumbleBridge {
    static let javaScript = #"""
    (function() {
        if (window.__gsRumble) return;
        window.__gsRumble = true;

        var hooked = typeof WeakSet !== "undefined" ? new WeakSet() : null;

        function send(data) {
            try {
                window.webkit.messageHandlers.gamestream.postMessage({
                    type: "rumble",
                    left: Number(data.leftMotorPercent) || 0,
                    right: Number(data.rightMotorPercent) || 0,
                    leftTrigger: Number(data.leftTriggerMotorPercent) || 0,
                    rightTrigger: Number(data.rightTriggerMotorPercent) || 0,
                    durationMs: Number(data.durationMs) || 0
                });
            } catch (e) {}
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
                send(data);
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
                if (!channel || channel.label !== "input") return;
                if (hooked) {
                    if (hooked.has(channel)) return;
                    hooked.add(channel);
                }
                channel.addEventListener("message", onMessage);
            } catch (e) {}
        }

        try {
            var create = RTCPeerConnection.prototype.createDataChannel;
            RTCPeerConnection.prototype.createDataChannel = function() {
                var channel = create.apply(this, arguments);
                hook(channel);
                return channel;
            };
        } catch (e) {}

        try {
            var addListener = RTCPeerConnection.prototype.addEventListener;
            RTCPeerConnection.prototype.addEventListener = function(type, listener, options) {
                if (type === "datachannel" && typeof listener === "function") {
                    var wrapped = function(event) {
                        try { if (event && event.channel) hook(event.channel); } catch (e) {}
                        return listener.apply(this, arguments);
                    };
                    return addListener.call(this, type, wrapped, options);
                }
                return addListener.call(this, type, listener, options);
            };
        } catch (e) {}

        // Ask the service to enable vibration in the stream configuration.
        try {
            var nativeFetch = window.fetch.bind(window);
            window.fetch = function(resource, init) {
                var url = typeof resource === "string" ? resource : (resource && resource.url) || "";
                var pending = nativeFetch(resource, init);
                if (!/\/configuration(\?|$)/.test(url)) return pending;
                return pending.then(function(response) {
                    return response.clone().text().then(function(text) {
                        try {
                            var body = JSON.parse(text);
                            var overrides = {};
                            try {
                                overrides = JSON.parse(body.clientStreamingConfigOverrides || "{}") || {};
                            } catch (e) { overrides = {}; }
                            overrides.inputConfiguration = overrides.inputConfiguration || {};
                            overrides.inputConfiguration.enableVibration = true;
                            body.clientStreamingConfigOverrides = JSON.stringify(overrides);
                            return new Response(JSON.stringify(body), {
                                status: response.status,
                                statusText: response.statusText,
                                headers: response.headers
                            });
                        } catch (e) {
                            return response;
                        }
                    }).catch(function() { return response; });
                });
            };
        } catch (e) {}
    })();
    """#

    @MainActor
    static func handle(payload: [String: Any]) {
        func number(_ key: String) -> Float {
            if let value = payload[key] as? NSNumber { return value.floatValue }
            if let value = payload[key] as? Double { return Float(value) }
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
}

/// Drives a physical controller's haptics from stream rumble packets.
@MainActor
final class ControllerRumble: ObservableObject {
    static let shared = ControllerRumble()

    @Published private(set) var controllerName: String?
    @Published private(set) var supportsHaptics = false

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var controllerID: ObjectIdentifier?
    private var isPlaying = false
    private var observers: [NSObjectProtocol] = []
    private var started = false

    /// Stops the motors when the packet's own duration elapses.
    ///
    /// This is the fix for rumble that never ended in 1.x: the duration field
    /// was parsed and then thrown away, so the haptic loop ran until a zero
    /// packet happened to arrive. If the game stopped sending — which happens
    /// whenever a session drops — the controller simply buzzed forever.
    private var stopTimer: Task<Void, Never>?
    private var stopDeadline: Date?

    private let log = AppLog.shared
    private static let loopDuration: TimeInterval = 1

    private init() {}

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
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        refreshController(reason: "start")
    }

    func play(left: Float, right: Float, leftTrigger: Float = 0,
              rightTrigger: Float = 0, durationMs: Double, force: Bool = false) {
        guard force || AppSettings.shared.rumbleEnabled else { return }

        let magnitudeLeft = scale(max(normalise(left), normalise(leftTrigger)))
        let magnitudeRight = scale(max(normalise(right), normalise(rightTrigger)))
        let intensity = min(max(magnitudeRight * 0.78 + magnitudeLeft * 0.48, 0), 1)

        guard intensity > 0.001 else {
            stop()
            return
        }
        guard prepareEngine() else { return }

        let sharpness = min(max(magnitudeLeft * 0.75 + magnitudeRight * 0.25, 0), 1) * 2 - 1
        apply(intensity: intensity, sharpness: sharpness)

        // A zero duration means "until further notice"; clamp anything longer
        // than a couple of seconds so a lost packet cannot strand the motors.
        let seconds = durationMs > 0 ? min(durationMs / 1000, 2.5) : 2.5
        // A deadline that one long-lived timer watches. Creating a task per
        // packet meant sixty allocations and cancellations a second during
        // heavy rumble.
        stopDeadline = Date().addingTimeInterval(seconds)
        startStopTimer()
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

    func stop() {
        stopTimer?.cancel()
        stopTimer = nil
        stopDeadline = nil
        guard isPlaying else { return }
        try? player?.stop(atTime: CHHapticTimeImmediate)
        isPlaying = false
    }

    func teardown() {
        stop()
        engine?.stop(completionHandler: nil)
        engine = nil
        player = nil
        controllerID = nil
    }

    // MARK: - Test patterns used by Settings

    func testLeft() { play(left: 1, right: 0, durationMs: 400, force: true) }
    func testRight() { play(left: 0, right: 1, durationMs: 400, force: true) }

    func testBoth() {
        testLeft()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            testRight()
            try? await Task.sleep(for: .milliseconds(600))
            play(left: 1, right: 1, durationMs: 350, force: true)
        }
    }

    // MARK: - Engine

    private func refreshController(reason: String) {
        let controller = activeController()
        controllerName = controller?.vendorName
        supportsHaptics = controller?.haptics != nil
        log.info("rumble", "\(reason): \(controllerName ?? "no controller")"
                 + (supportsHaptics ? " with haptics" : " without haptics"))
        if controller == nil { teardown() }
    }

    private func activeController() -> GCController? {
        if let current = GCController.current, current.haptics != nil { return current }
        let all = GCController.controllers()
        return all.first { $0.haptics != nil } ?? all.first
    }

    private func prepareEngine() -> Bool {
        guard let controller = activeController(), let haptics = controller.haptics else {
            return false
        }
        let id = ObjectIdentifier(controller)
        if controllerID == id, player != nil { return true }

        teardown()
        controllerID = id

        guard let engine = haptics.createEngine(withLocality: .default) else {
            log.error("rumble", "could not create a haptic engine for \(controller.vendorName ?? "controller")")
            return false
        }
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
            try engine.start()

            self.engine = engine
            self.player = advanced
            log.info("rumble", "haptics ready on \(controller.vendorName ?? "controller")")
            return true
        } catch {
            log.error("rumble", "haptic setup failed: \(error.localizedDescription)")
            self.engine = nil
            self.player = nil
            controllerID = nil
            return false
        }
    }

    private func engineDidStop() {
        isPlaying = false
        player = nil
        engine = nil
        controllerID = nil
    }

    private func apply(intensity: Float, sharpness: Float) {
        guard let player else { return }
        let parameters = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: sharpness, relativeTime: 0)
        ]
        do {
            if !isPlaying {
                try player.start(atTime: CHHapticTimeImmediate)
                isPlaying = true
            }
            try player.sendParameters(parameters, atTime: CHHapticTimeImmediate)
        } catch {
            log.warn("rumble", "playback failed: \(error.localizedDescription)")
            engineDidStop()
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
