import Foundation
import GameController
import CoreHaptics

/// Native controller rumble bridge for Xbox / MFi / supported Bluetooth controllers.
///
/// The web player sends standard weak/strong magnitudes through XboxCloudWebView.
/// This class translates those requests into Core Haptics on the controller's
/// actual handle actuators instead of relying on a generic/default locality.
///
/// Crash isolation:
/// - No controller or haptic engine is touched at process launch.
/// - Engines are created lazily on the first rumble request.
/// - Controller disconnects/reset are handled by rebuilding the engines.
/// - Every hardware/API failure is best-effort and swallowed.
@MainActor
final class ControllerRumble {
    static let shared = ControllerRumble()

    private static let intensityKey = "GameStream.controllerRumbleIntensity"
    private static let enabledKey = "GameStream.controllerHapticsEnabled"

    /// Software gain before the user's intensity setting.
    private let baseGain: Float = 2.4
    private let minimumOutput: Float = 0.16

    private var leftEngine: CHHapticEngine?
    private var rightEngine: CHHapticEngine?
    private var controllerID: ObjectIdentifier?
    private var leftSupported = false
    private var rightSupported = false
    private var stopWorkItem: DispatchWorkItem?

    private init() {}

    private var userIntensity: Float {
        let stored = UserDefaults.standard.object(forKey: Self.intensityKey) as? Double
        return min(max(Float(stored ?? 1.6), 0.5), 3.0)
    }

    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Plays a dual-handle rumble. The weak/strong values are intentionally
    /// mapped to left/right handle energy so both physical handle actuators
    /// receive output on controllers that expose separate handle haptics.
    func play(weak: Float, strong: Float, durationMs: Double, force: Bool = false) {
        guard force || isEnabled else { return }

        let weakValue = boosted(weak)
        let strongValue = boosted(strong)

        guard weakValue > 0 || strongValue > 0 else {
            stop()
            return
        }

        do {
            try ensureEngines()

            let duration = min(max(durationMs / 1000.0, 0.025), 2.5)
            var played = false

            if leftSupported, let leftEngine {
                played = try play(on: leftEngine, intensity: weakValue, duration: duration) || played
            }

            if rightSupported, let rightEngine {
                played = try play(on: rightEngine, intensity: strongValue, duration: duration) || played
            }

            // Some controllers expose only the combined handle locality.
            // Fall back to the strongest signal instead of silently dropping
            // rumble altogether.
            if !played {
                try playCombinedFallback(weak: weakValue, strong: strongValue, duration: duration)
            }

            scheduleStop(after: duration)
        } catch {
            teardownEngines()
        }
    }

    /// Settings test: produces a clearly audible/physical dual pulse.
    func playTest() {
        play(weak: 1.0, strong: 1.0, durationMs: 260, force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) { [weak self] in
            Task { @MainActor in
                self?.play(weak: 0.8, strong: 1.0, durationMs: 220, force: true)
            }
        }
    }

    func stop() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        // Stopping the engine is intentionally avoided for every shot. The
        // controller haptic engine is kept warm so rapid COD gunfire does not
        // pay an engine restart penalty.
    }

    func teardown() {
        stop()
        teardownEngines()
    }

    private func boosted(_ value: Float) -> Float {
        let raw = min(max(value, 0), 1)
        guard raw > 0.005 else { return 0 }
        let scaled = min(raw * baseGain * userIntensity, 1)
        return max(scaled, minimumOutput)
    }

    private func ensureEngines() throws {
        let controllers = GCController.controllers()

        // Prefer the active controller, then any controller that actually
        // advertises haptics. This avoids accidentally attaching rumble to a
        // stale/snapshot controller.
        guard let controller =
            GCController.current ??
            controllers.first(where: { $0.haptics != nil }) ??
            controllers.first
        else {
            throw RumbleError.noController
        }

        let id = ObjectIdentifier(controller)

        if controllerID == id, leftEngine != nil || rightEngine != nil {
            return
        }

        teardownEngines()

        guard let haptics = controller.haptics else {
            throw RumbleError.noHaptics
        }

        let localities = haptics.supportedLocalities

        if localities.contains(.leftHandle),
           let engine = haptics.createEngine(withLocality: .leftHandle) {
            configure(engine)
            try engine.start()
            leftEngine = engine
            leftSupported = true
            installHandlers(on: engine)
        }

        if localities.contains(.rightHandle),
           let engine = haptics.createEngine(withLocality: .rightHandle) {
            configure(engine)
            try engine.start()
            rightEngine = engine
            rightSupported = true
            installHandlers(on: engine)
        }

        // A number of controllers expose only the aggregate handles locality.
        // Keep a combined engine as a fallback in that case.
        if !leftSupported && !rightSupported,
           localities.contains(.handles),
           let engine = haptics.createEngine(withLocality: .handles) {
            configure(engine)
            try engine.start()
            leftEngine = engine
            leftSupported = true
            installHandlers(on: engine)
        }

        guard leftSupported || rightSupported else {
            throw RumbleError.unsupportedLocality
        }

        controllerID = id
    }

    private func configure(_ engine: CHHapticEngine) {
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
    }

    private func installHandlers(on engine: CHHapticEngine) {
        engine.resetHandler = { [weak self] in
            Task { @MainActor in
                self?.teardownEngines()
            }
        }

        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in
                self?.teardownEngines()
            }
        }
    }

    @discardableResult
    private func play(
        on engine: CHHapticEngine,
        intensity: Float,
        duration: TimeInterval
    ) throws -> Bool {
        guard intensity > 0.005 else { return false }

        let pattern = try CHHapticPattern(
            events: [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: min(max(intensity, 0), 1)
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: 0.35
                        )
                    ],
                    relativeTime: 0,
                    duration: duration
                )
            ],
            parameters: []
        )

        let player = try engine.makeAdvancedPlayer(with: pattern)
        try player.start(atTime: 0)
        return true
    }

    private func playCombinedFallback(
        weak: Float,
        strong: Float,
        duration: TimeInterval
    ) throws {
        let engine = leftEngine ?? rightEngine
        guard let engine else { return }

        let intensity = min(max(max(weak, strong), 0), 1)
        _ = try play(on: engine, intensity: intensity, duration: duration)
    }

    private func scheduleStop(after duration: TimeInterval) {
        stopWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.stopWorkItem = nil
            }
        }

        stopWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + duration + 0.05,
            execute: item
        )
    }

    private func teardownEngines() {
        stopWorkItem?.cancel()
        stopWorkItem = nil

        leftEngine?.stop(completionHandler: nil)
        rightEngine?.stop(completionHandler: nil)

        leftEngine = nil
        rightEngine = nil
        leftSupported = false
        rightSupported = false
        controllerID = nil
    }

    private enum RumbleError: Error {
        case noController
        case noHaptics
        case unsupportedLocality
    }
}
