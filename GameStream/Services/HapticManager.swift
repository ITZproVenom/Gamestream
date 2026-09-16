import UIKit
import GameController
import CoreHaptics

/// Dual-path haptics: Taptic Engine + controller rumble when a gamepad is
/// connected. Everything is lazy — GameController / CoreHaptics are touched
/// only from an explicit play() after launch, and every failure is swallowed
/// so a haptics bug can never take down the app.
///
/// Controller path: one CHHapticEngine per controller (default + handles
/// localities) is created once and kept alive for the life of the connection,
/// instead of rebuilding an engine per tap. Unlike the old code, no device
/// Taptic-Engine capability check is applied to the controller path — a
/// connected gamepad vibrates even on iPads that have no iPhone-style haptics.
enum HapticManager {
    enum Style {
        case light, medium, heavy, success, error
    }

    static func play(_ style: Style = .light) {
        playDevice(style)
        playController(style)
    }

    static func tap() { play(.light) }
    static func impact() { play(.medium) }
    static func success() { play(.success) }
    static func error() { play(.error) }

    // MARK: - Device (Taptic Engine)

    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    private static func playDevice(_ style: Style) {
        switch style {
        case .light:
            deviceImpact(.light)
        case .medium:
            deviceImpact(.medium)
        case .heavy:
            deviceImpact(.heavy)
        case .success:
            notificationGenerator.notificationOccurred(.success)
        case .error:
            notificationGenerator.notificationOccurred(.error)
        }
    }

    private static func deviceImpact(_ feedback: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator: UIImpactFeedbackGenerator
        if let cached = impactGenerators[feedback] {
            generator = cached
        } else {
            let made = UIImpactFeedbackGenerator(style: feedback)
            impactGenerators[feedback] = made
            generator = made
        }
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Controller rumble

    private static var controllerHapticsEnabled: Bool {
        if UserDefaults.standard.object(forKey: "GameStream.controllerHapticsEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "GameStream.controllerHapticsEnabled")
    }

    private static var engineCache: [ObjectIdentifier: ControllerHaptics] = [:]
    private static var observersRegistered = false

    /// Holds the per-locality engines for one connected controller.
    final class ControllerHaptics {
        let controller: GCController
        var defaultEngine: CHHapticEngine?
        var handlesEngine: CHHapticEngine?

        init(_ controller: GCController) {
            self.controller = controller
        }

        func engine(for locality: GCHapticsLocality, haptics: GCDeviceHaptics) -> CHHapticEngine? {
            let existing = locality == GCHapticsLocality.handles ? handlesEngine : defaultEngine
            if let existing { return existing }
            guard let engine = haptics.createEngine(withLocality: locality) else { return nil }
            // Keep the motor warm; the next play() restarts a stopped/reset engine.
            engine.isAutoShutdownEnabled = false
            if locality == GCHapticsLocality.handles {
                handlesEngine = engine
            } else {
                defaultEngine = engine
            }
            return engine
        }

        func shutdown() {
            defaultEngine?.stop(completionHandler: nil)
            handlesEngine?.stop(completionHandler: nil)
            defaultEngine = nil
            handlesEngine = nil
        }
    }

    /// Registers connect/disconnect observers once, lazily, on first use.
    private static func ensureObservers() {
        guard !observersRegistered else { return }
        observersRegistered = true
        let center = NotificationCenter.default
        _ = center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { _ in
            pruneEngines()
        }
        _ = center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in
            pruneEngines()
        }
    }

    /// Drops + shuts down engines for controllers that are no longer connected.
    private static func pruneEngines() {
        let connected = GCController.controllers()
        let connectedIDs = Set(connected.map { ObjectIdentifier($0) })
        let stale = engineCache.keys.filter { !connectedIDs.contains($0) }
        for id in stale {
            engineCache[id]?.shutdown()
            engineCache[id] = nil
        }
    }

    private static func playController(_ style: Style) {
        guard controllerHapticsEnabled else { return }
        let connected = GCController.controllers()
        guard !connected.isEmpty else { return }

        ensureObservers()
        pruneEngines()

        guard let pattern = controllerPattern(for: style) else { return }

        for controller in connected {
            guard let haptics = controller.haptics else { continue }
            let entry: ControllerHaptics
            let id = ObjectIdentifier(controller)
            if let cached = engineCache[id] {
                entry = cached
            } else {
                let made = ControllerHaptics(controller)
                engineCache[id] = made
                entry = made
            }

            for locality in [GCHapticsLocality.default, GCHapticsLocality.handles] {
                guard let engine = entry.engine(for: locality, haptics: haptics) else { continue }
                do {
                    // start() is a no-op when the engine is already running, so
                    // a stopped/reset engine is simply restarted on next play.
                    try engine.start()
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: 0)
                } catch {
                    continue
                }
            }
        }
    }

    /// Stronger, longer pulses than the Taptic pattern so a controller's motor
    /// actually feels them; success/error get a two-part burst.
    private static func controllerPattern(for style: Style) -> CHHapticPattern? {
        let intensity: Float
        let sharpness: Float
        let duration: TimeInterval
        let secondAt: TimeInterval?

        switch style {
        case .light:
            intensity = 0.6; sharpness = 0.4; duration = 0.12; secondAt = nil
        case .medium:
            intensity = 0.8; sharpness = 0.3; duration = 0.16; secondAt = nil
        case .heavy:
            intensity = 1.0; sharpness = 0.2; duration = 0.2; secondAt = nil
        case .success:
            intensity = 0.7; sharpness = 0.5; duration = 0.1; secondAt = 0.12
        case .error:
            intensity = 0.9; sharpness = 0.15; duration = 0.18; secondAt = 0.06
        }

        var events = [CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0,
            duration: duration
        )]

        if let secondAt {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: secondAt,
                duration: 0.06
            ))
        }

        return try? CHHapticPattern(events: events, parameters: [])
    }

    @discardableResult
    static func controllerConnected() -> Bool {
        !GCController.controllers().isEmpty
    }
}