import Foundation
import GameController
import CoreHaptics
import os

/// Drives physical controller rumble motors via GCDeviceHaptics.
///
/// Engines are created once per connected pad and kept alive for the whole
/// play session so rapid Xbox Cloud packets (Call of Duty gunfire, explosions)
/// are not lost to engine restarts. Pattern players are retained until their
/// duration elapses — Core Haptics on GCDeviceHaptics will otherwise deallocate
/// the player immediately and the motors never spin.
@MainActor
final class ControllerRumble {
    static let shared = ControllerRumble()

    private enum Defaults {
        static let enabled = "GameStream.controllerHapticsEnabled"
        static let intensity = "GameStream.controllerRumbleIntensity"
    }

    private final class Motor {
        let locality: GCHapticsLocality
        let engine: CHHapticEngine
        var players: [any CHHapticPatternPlayer] = []
        var started = false

        init(locality: GCHapticsLocality, engine: CHHapticEngine, started: Bool) {
            self.locality = locality
            self.engine = engine
            self.started = started
        }
    }

    private let logger = Logger(subsystem: "com.gamestream.app", category: "Rumble")
    private var motors: [GCHapticsLocality: Motor] = [:]
    private var controllerID: ObjectIdentifier?
    private var lastLoggedControllerName: String?
    private var lastPacketLogAt: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var didStart = false
    private var generation = 0

    private init() {}

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Defaults.enabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Defaults.enabled)
    }

    var connectedControllerName: String? { activeController()?.vendorName }

    var supportsRumble: Bool { activeController()?.haptics != nil }

    /// Call once at launch so connect/disconnect is observed before the first stream.
    func start() {
        guard !didStart else { return }
        didStart = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                self?.handleConnect(note.object as? GCController)
            }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                self?.handleDisconnect(note.object as? GCController)
            }
        })
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        attach(reason: "start")
    }

    /// Xbox Cloud FourMotorRumble packet. Percents may be 0...1 or 0...100.
    func play(
        leftMotorPercent: Float,
        rightMotorPercent: Float,
        leftTriggerMotorPercent: Float = 0,
        rightTriggerMotorPercent: Float = 0,
        durationMs: Double,
        force: Bool = false
    ) {
        guard force || isEnabled else { return }
        let left = scale(normalize(leftMotorPercent))
        let right = scale(normalize(rightMotorPercent))
        let leftTrigger = scale(normalize(leftTriggerMotorPercent))
        let rightTrigger = scale(normalize(rightTriggerMotorPercent))
        let duration = min(max(durationMs / 1000, 0), 4)

        logPacket(left: left, right: right, leftTrigger: leftTrigger, rightTrigger: rightTrigger, durationMs: durationMs)

        let anyMotor = left > 0 || right > 0 || leftTrigger > 0 || rightTrigger > 0
        if !anyMotor {
            stopMotors()
            return
        }
        guard attach(reason: "play") else { return }
        let playDuration = duration > 0 ? duration : 0.05

        do {
            var played = false
            if left > 0 {
                played = try pulse(.leftHandle, intensity: left, sharpness: 0.12, duration: playDuration) || played
            }
            if right > 0 {
                played = try pulse(.rightHandle, intensity: right, sharpness: 0.82, duration: playDuration) || played
            }
            if leftTrigger > 0 {
                played = try pulse(.leftTrigger, intensity: leftTrigger, sharpness: 0.95, duration: playDuration) || played
            }
            if rightTrigger > 0 {
                played = try pulse(.rightTrigger, intensity: rightTrigger, sharpness: 0.95, duration: playDuration) || played
            }
            if !played {
                let intensity = max(left, right, leftTrigger, rightTrigger)
                let sharpness: Float = right >= left ? 0.7 : 0.2
                if try pulse(.handles, intensity: intensity, sharpness: sharpness, duration: playDuration) {
                    played = true
                } else if try pulse(.default, intensity: intensity, sharpness: sharpness, duration: playDuration) {
                    played = true
                }
            }
            if played {
                logger.debug("native rumble dispatched L=\(left, format: .fixed(precision: 2)) R=\(right, format: .fixed(precision: 2)) d=\(durationMs, format: .fixed(precision: 0))ms")
            } else {
                logger.error("haptic engine failure: no locality accepted the pulse")
            }
        } catch {
            logger.error("haptic engine failure: \(error.localizedDescription, privacy: .public)")
            invalidateEngines()
        }
    }

    /// Back-compat wrapper used by older call sites (weak = left, strong = right).
    func play(weak: Float, strong: Float, durationMs: Double, force: Bool = false) {
        play(
            leftMotorPercent: weak,
            rightMotorPercent: strong,
            durationMs: durationMs,
            force: force
        )
    }

    func testLeft() {
        guard attach(reason: "testLeft") else {
            logger.error("test Left: no haptics-capable controller")
            return
        }
        do {
            if motors[.leftHandle] != nil {
                _ = try pulse(.leftHandle, intensity: scale(1), sharpness: 0.12, duration: 0.45)
            } else {
                logger.debug("test Left: .leftHandle missing, using aggregate handles")
                if !(try pulse(.handles, intensity: scale(1), sharpness: 0.12, duration: 0.45)) {
                    _ = try pulse(.default, intensity: scale(1), sharpness: 0.12, duration: 0.45)
                }
            }
        } catch {
            logger.error("test Left failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func testRight() {
        guard attach(reason: "testRight") else {
            logger.error("test Right: no haptics-capable controller")
            return
        }
        do {
            if motors[.rightHandle] != nil {
                _ = try pulse(.rightHandle, intensity: scale(1), sharpness: 0.82, duration: 0.45)
            } else {
                logger.debug("test Right: .rightHandle missing, using aggregate handles")
                if !(try pulse(.handles, intensity: scale(1), sharpness: 0.82, duration: 0.45)) {
                    _ = try pulse(.default, intensity: scale(1), sharpness: 0.82, duration: 0.45)
                }
            }
        } catch {
            logger.error("test Right failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func playTest() {
        testLeft()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            Task { @MainActor in self?.testRight() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            Task { @MainActor in
                self?.play(
                    leftMotorPercent: 1,
                    rightMotorPercent: 1,
                    durationMs: 350,
                    force: true
                )
            }
        }
    }

    func teardown() {
        invalidateEngines()
    }

    func noteNativeLog(_ event: String, details: String) {
        switch event {
        case "packet":
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastPacketLogAt < 1 { return }
            lastPacketLogAt = now
            logger.debug("vibration packet received \(details, privacy: .public)")
        case "inputChannel":
            logger.info("input data channel discovered \(details, privacy: .public)")
        case "bridgeReady":
            logger.info("rumble JS bridge ready \(details, privacy: .public)")
        case "parseError", "hookError":
            logger.error("rumble JS \(event, privacy: .public): \(details, privacy: .public)")
        default:
            logger.debug("rumble JS \(event, privacy: .public) \(details, privacy: .public)")
        }
    }

    @discardableResult
    private func attach(reason: String) -> Bool {
        guard let controller = activeController() else {
            if reason != "play" {
                logger.debug("no controller connected (\(reason, privacy: .public))")
            }
            invalidateEngines()
            return false
        }
        guard let haptics = controller.haptics else {
            let name = controller.vendorName ?? "unknown"
            if lastLoggedControllerName != name {
                lastLoggedControllerName = name
                logger.error("controller discovered '\(name, privacy: .public)' but haptics unsupported (GCDeviceHaptics is nil). Public GameController API cannot drive this pad's motors.")
            }
            invalidateEngines()
            return false
        }

        let id = ObjectIdentifier(controller)
        if controllerID == id, !motors.isEmpty {
            restartStoppedEngines()
            return true
        }

        invalidateEngines()
        controllerID = id
        let localities = haptics.supportedLocalities
        let names = localities.map { localityName($0) }.sorted().joined(separator: ",")
        logger.info("controller discovered '\(controller.vendorName ?? "unknown", privacy: .public)' haptics supported localities=[\(names, privacy: .public)]")

        let wanted: [GCHapticsLocality] = [
            .leftHandle, .rightHandle, .handles, .default, .leftTrigger, .rightTrigger
        ]
        for locality in wanted where localities.contains(locality) {
            guard let engine = haptics.createEngine(withLocality: locality) else { continue }
            do {
                try configure(engine, locality: locality)
                motors[locality] = Motor(locality: locality, engine: engine, started: true)
            } catch {
                logger.error("haptic engine failure starting \(self.localityName(locality), privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if motors.isEmpty {
            logger.error("haptics supported but every createEngine(withLocality:) failed")
            return false
        }
        return true
    }

    private func configure(_ engine: CHHapticEngine, locality: GCHapticsLocality) throws {
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        let g = generation
        let name = localityName(locality)
        engine.resetHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == g else { return }
                self.logger.debug("haptic engine reset \(name, privacy: .public) — restarting")
                self.restart(locality)
            }
        }
        engine.stoppedHandler = { [weak self] reason in
            Task { @MainActor in
                guard let self, self.generation == g else { return }
                self.logger.debug("haptic engine stopped \(name, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
                if reason == .gameControllerDisconnect {
                    self.invalidateEngines()
                } else {
                    self.restart(locality)
                }
            }
        }
        try engine.start()
    }

    private func restart(_ locality: GCHapticsLocality) {
        guard let motor = motors[locality] else { return }
        motor.players.removeAll()
        do {
            try motor.engine.start()
            motor.started = true
        } catch {
            logger.error("haptic engine failure restarting \(self.localityName(locality), privacy: .public): \(error.localizedDescription, privacy: .public)")
            motor.started = false
        }
    }

    private func restartStoppedEngines() {
        for (locality, motor) in motors where !motor.started {
            restart(locality)
        }
    }

    @discardableResult
    private func pulse(
        _ locality: GCHapticsLocality,
        intensity: Float,
        sharpness: Float,
        duration: TimeInterval
    ) throws -> Bool {
        guard intensity > 0.005 else { return false }
        guard let motor = motors[locality] else { return false }
        if !motor.started {
            try motor.engine.start()
            motor.started = true
        }
        let clampedDuration = min(max(duration, 0.02), 4)
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(max(intensity, 0), 1)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: min(max(sharpness, 0), 1))
            ],
            relativeTime: 0,
            duration: clampedDuration
        )
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        let player = try motor.engine.makePlayer(with: pattern)
        motor.players.append(player)
        if motor.players.count > 32 {
            motor.players.removeFirst(motor.players.count - 32)
        }
        try player.start(atTime: 0)

        let token = ObjectIdentifier(player as AnyObject)
        DispatchQueue.main.asyncAfter(deadline: .now() + clampedDuration + 0.08) { [weak self] in
            Task { @MainActor in
                self?.releasePlayer(locality: locality, token: token)
            }
        }
        return true
    }

    private func releasePlayer(locality: GCHapticsLocality, token: ObjectIdentifier) {
        guard let motor = motors[locality] else { return }
        motor.players.removeAll { ObjectIdentifier($0 as AnyObject) == token }
    }

    private func stopMotors() {
        for motor in motors.values {
            for player in motor.players {
                try? player.stop(atTime: 0)
            }
            motor.players.removeAll()
        }
    }

    private func handleConnect(_ controller: GCController?) {
        let name = controller?.vendorName ?? "unknown"
        let haptics = controller?.haptics != nil
        logger.info("controller connected '\(name, privacy: .public)' haptics=\(haptics, privacy: .public)")
        attach(reason: "connect")
    }

    private func handleDisconnect(_ controller: GCController?) {
        let name = controller?.vendorName ?? "unknown"
        logger.info("controller disconnected '\(name, privacy: .public)'")
        if let controller, controllerID == ObjectIdentifier(controller) {
            invalidateEngines()
        }
        attach(reason: "disconnect")
    }

    private func activeController() -> GCController? {
        let connected = GCController.controllers()
        if let current = GCController.current, current.haptics != nil {
            return current
        }
        if let haptic = connected.first(where: { $0.haptics != nil }) {
            return haptic
        }
        return connected.first(where: { $0.extendedGamepad != nil }) ?? connected.first
    }

    private func normalize(_ value: Float) -> Float {
        if value > 1 { return min(max(value / 100, 0), 1) }
        return min(max(value, 0), 1)
    }

    private func scale(_ value: Float) -> Float {
        let raw = min(max(value, 0), 1)
        guard raw > 0.005 else { return 0 }
        let stored = UserDefaults.standard.object(forKey: Defaults.intensity) as? Double
        let intensity = min(max(Float(stored ?? 1.6), 0.5), 3)
        return min(max(raw * intensity, 0.05), 1)
    }

    private func invalidateEngines() {
        generation &+= 1
        for motor in motors.values {
            for player in motor.players {
                try? player.stop(atTime: 0)
            }
            motor.engine.stop(completionHandler: nil)
        }
        motors.removeAll()
        controllerID = nil
    }

    private func localityName(_ locality: GCHapticsLocality) -> String {
        switch locality {
        case .leftHandle: return "leftHandle"
        case .rightHandle: return "rightHandle"
        case .handles: return "handles"
        case .leftTrigger: return "leftTrigger"
        case .rightTrigger: return "rightTrigger"
        case .triggers: return "triggers"
        case .default: return "default"
        default: return locality.rawValue
        }
    }

    private func logPacket(left: Float, right: Float, leftTrigger: Float, rightTrigger: Float, durationMs: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPacketLogAt < 1 { return }
        lastPacketLogAt = now
        logger.debug("parsed motor values L=\(left, format: .fixed(precision: 2)) R=\(right, format: .fixed(precision: 2)) LT=\(leftTrigger, format: .fixed(precision: 2)) RT=\(rightTrigger, format: .fixed(precision: 2)) d=\(durationMs, format: .fixed(precision: 0))ms")
    }
}
