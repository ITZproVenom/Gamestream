import Foundation
import GameController
import CoreHaptics
import os

/// Drives physical controller rumble using a persistent Core Haptics playback loop.
@MainActor
final class ControllerRumble {
    static let shared = ControllerRumble()

    private enum Defaults {
        static let enabled = "GameStream.controllerHapticsEnabled"
        static let intensity = "GameStream.controllerRumbleIntensity"
    }

    private struct RumbleProfile: Equatable {
        let intensity: Float
        let sharpnessControl: Float

        init(leftMagnitude: Float, rightMagnitude: Float) {
            let left = min(max(leftMagnitude, 0), 1)
            let right = min(max(rightMagnitude, 0), 1)
            intensity = min(max((right * 0.78) + (left * 0.48), 0), 1)
            let sharpness = min(max((left * 0.75) + (right * 0.25), 0), 1)
            sharpnessControl = (sharpness * 2) - 1
        }

        var isStopped: Bool { intensity <= 0.001 }

        func materiallyDiffers(from other: RumbleProfile) -> Bool {
            abs(intensity - other.intensity) >= 0.04
                || abs(sharpnessControl - other.sharpnessControl) >= 0.08
        }
    }

    private final class HapticPlayback {
        static let loopDuration: TimeInterval = 1

        let engine: CHHapticEngine
        let player: CHHapticAdvancedPatternPlayer
        let controllerIdentifier: ObjectIdentifier

        var isPlaying = false
        var lastProfile: RumbleProfile?
        var lastUpdateAt: TimeInterval = 0

        init(engine: CHHapticEngine, controllerIdentifier: ObjectIdentifier) throws {
            self.engine = engine
            self.controllerIdentifier = controllerIdentifier

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
            player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = Self.loopDuration
        }

        func stopPlayer() {
            if isPlaying {
                try? player.stop(atTime: CHHapticTimeImmediate)
            }
            isPlaying = false
            lastProfile = nil
            lastUpdateAt = 0
        }

        func shutdown() {
            stopPlayer()
            engine.stop(completionHandler: nil)
        }

        func markEngineStopped() {
            isPlaying = false
            lastProfile = nil
            lastUpdateAt = 0
        }
    }

    private let logger = Logger(subsystem: "com.gamestream.app", category: "Rumble")
    private static let hapticUpdateInterval: TimeInterval = 0.035

    private var playback: HapticPlayback?
    private var controllerID: ObjectIdentifier?
    private var observers: [NSObjectProtocol] = []
    private var didStart = false
    private var generation = 0
    private var lastLoggedControllerName: String?
    private var lastPacketLogAt: TimeInterval = 0

    private init() {}

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Defaults.enabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Defaults.enabled)
    }

    var connectedControllerName: String? {
        activeController()?.vendorName
    }

    var supportsRumble: Bool {
        activeController()?.haptics != nil
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleConnect(note.object as? GCController)
            }
        })

        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleDisconnect(note.object as? GCController)
            }
        })

        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        attach(reason: "start")
    }

    /// Xbox Cloud FourMotorRumble packet.
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

        logPacket(
            left: left,
            right: right,
            leftTrigger: leftTrigger,
            rightTrigger: rightTrigger,
            durationMs: durationMs
        )

        let profile = RumbleProfile(
            leftMagnitude: max(left, leftTrigger),
            rightMagnitude: max(right, rightTrigger)
        )

        if profile.isStopped {
            stopRumble()
            return
        }

        guard attach(reason: "play") else { return }

        do {
            try updatePlayback(profile)
            logger.debug(
                "native rumble dispatched L=\(left, format: .fixed(precision: 2)) R=\(right, format: .fixed(precision: 2)) d=\(durationMs, format: .fixed(precision: 0))ms"
            )
        } catch {
            logger.error("haptic engine failure: \(error.localizedDescription, privacy: .public)")
            invalidatePlayback()
        }
    }

    func play(weak: Float, strong: Float, durationMs: Double, force: Bool = false) {
        play(
            leftMotorPercent: weak,
            rightMotorPercent: strong,
            durationMs: durationMs,
            force: force
        )
    }

    func testLeft() {
        play(leftMotorPercent: 1, rightMotorPercent: 0, durationMs: 450, force: true)
    }

    func testRight() {
        play(leftMotorPercent: 0, rightMotorPercent: 1, durationMs: 450, force: true)
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
        invalidatePlayback()
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
            invalidatePlayback()
            return false
        }

        guard let haptics = controller.haptics else {
            let name = controller.vendorName ?? "unknown"
            if lastLoggedControllerName != name {
                lastLoggedControllerName = name
                logger.error(
                    "controller discovered '\(name, privacy: .public)' but haptics unsupported"
                )
            }
            invalidatePlayback()
            return false
        }

        let id = ObjectIdentifier(controller)
        if controllerID == id, playback != nil {
            restartStoppedPlayback()
            return true
        }

        invalidatePlayback()
        controllerID = id

        guard let engine = haptics.createEngine(withLocality: .default) else {
            logger.error("haptic engine creation failed for default locality")
            return false
        }

        do {
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false

            let next = try HapticPlayback(
                engine: engine,
                controllerIdentifier: id
            )
            installCallbacks(next)
            playback = next

            let localities = haptics.supportedLocalities.map(localityName).sorted().joined(separator: ",")
            logger.info(
                "controller haptics ready '\(controller.vendorName ?? "unknown", privacy: .public)' localities=[\(localities, privacy: .public)]"
            )
            return true
        } catch {
            engine.stop(completionHandler: nil)
            controllerID = nil
            logger.error("haptic playback creation failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func updatePlayback(_ profile: RumbleProfile) throws {
        guard let playback else {
            throw NSError(domain: "GameStream.ControllerRumble", code: 1)
        }

        let now = ProcessInfo.processInfo.systemUptime
        if playback.isPlaying,
           now - playback.lastUpdateAt < Self.hapticUpdateInterval,
           let previous = playback.lastProfile,
           !profile.materiallyDiffers(from: previous) {
            return
        }

        let parameters = [
            CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: profile.intensity,
                relativeTime: 0
            ),
            CHHapticDynamicParameter(
                parameterID: .hapticSharpnessControl,
                value: profile.sharpnessControl,
                relativeTime: 0
            )
        ]

        if playback.isPlaying {
            try playback.player.sendParameters(
                parameters,
                atTime: CHHapticTimeImmediate
            )
        } else {
            try playback.engine.start()
            playback.player.isMuted = true
            try playback.player.start(atTime: CHHapticTimeImmediate)
            try playback.player.sendParameters(
                parameters,
                atTime: CHHapticTimeImmediate
            )
            playback.player.isMuted = false
            playback.isPlaying = true
        }

        playback.lastProfile = profile
        playback.lastUpdateAt = now
    }

    private func installCallbacks(_ playback: HapticPlayback) {
        let generation = self.generation
        let invalidate = { [weak self, weak playback] in
            Task { @MainActor in
                guard let self, let playback, self.playback === playback else { return }
                playback.markEngineStopped()
                self.playback = nil
                self.controllerID = nil
            }
        }

        playback.engine.stoppedHandler = { _ in
            invalidate()
        }

        playback.engine.resetHandler = {
            invalidate()
        }

        _ = generation
    }

    private func restartStoppedPlayback() {
        guard let playback, !playback.isPlaying else { return }
        do {
            try playback.engine.start()
            playback.isPlaying = false
        } catch {
            logger.error("haptic engine restart failed: \(error.localizedDescription, privacy: .public)")
            invalidatePlayback()
        }
    }

    private func stopRumble() {
        playback?.stopPlayer()
    }

    private func handleConnect(_ controller: GCController?) {
        logger.info(
            "controller connected '\(controller?.vendorName ?? "unknown", privacy: .public)' haptics=\(controller?.haptics != nil, privacy: .public)"
        )
        attach(reason: "connect")
    }

    private func handleDisconnect(_ controller: GCController?) {
        logger.info("controller disconnected '\(controller?.vendorName ?? "unknown", privacy: .public)'")
        if let controller, controllerID == ObjectIdentifier(controller) {
            invalidatePlayback()
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
        if value > 1 {
            return min(max(value / 100, 0), 1)
        }
        return min(max(value, 0), 1)
    }

    private func scale(_ value: Float) -> Float {
        let raw = min(max(value, 0), 1)
        guard raw > 0.005 else { return 0 }

        let stored = UserDefaults.standard.object(forKey: Defaults.intensity) as? Double
        let intensity = min(max(Float(stored ?? 1.6), 0.5), 3)
        return min(max(raw * intensity, 0.05), 1)
    }

    private func invalidatePlayback() {
        generation &+= 1
        playback?.shutdown()
        playback = nil
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

    private func logPacket(
        left: Float,
        right: Float,
        leftTrigger: Float,
        rightTrigger: Float,
        durationMs: Double
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPacketLogAt < 1 { return }
        lastPacketLogAt = now
        logger.debug(
            "parsed motor values L=\(left, format: .fixed(precision: 2)) R=\(right, format: .fixed(precision: 2)) LT=\(leftTrigger, format: .fixed(precision: 2)) RT=\(rightTrigger, format: .fixed(precision: 2)) d=\(durationMs, format: .fixed(precision: 0))ms"
        )
    }
}
