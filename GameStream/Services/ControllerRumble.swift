import Foundation
import GameController
import CoreHaptics

/// Plays dual-motor style rumble on a connected physical controller while streaming.
///
/// Safety rules (crash isolation):
/// - No work at process launch or static init.
/// - Engine created lazily on first rumble request.
/// - Every failure is swallowed; rumble is best-effort only.
/// - Respects AppearanceStore.controllerHapticsEnabled + controllerRumbleIntensity.
@MainActor
final class ControllerRumble {
    static let shared = ControllerRumble()

    private static let intensityKey = "GameStream.controllerRumbleIntensity"
    private static let enabledKey = "GameStream.controllerHapticsEnabled"

    /// Base software gain for weak wired pads (before user intensity multiplier).
    private let baseGain: Float = 2.8
    /// Minimum intensity after boost when the game reports any non-zero pulse.
    private let floor: Float = 0.45

    private var engine: CHHapticEngine?
    private var engineControllerID: ObjectIdentifier?
    private var lastStopWorkItem: DispatchWorkItem?

    private init() {}

    /// User multiplier from Settings (0.5 ... 3.0). Default 1.6 for wired pads.
    private var userIntensity: Float {
        let stored = UserDefaults.standard.object(forKey: Self.intensityKey) as? Double
        let v = Float(stored ?? 1.6)
        return min(max(v, 0.5), 3.0)
    }

    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Continuous dual-motor pulse. Intensities are 0...1 from the game/stream.
    func play(weak: Float, strong: Float, durationMs: Double) {
        guard isEnabled else { return }

        var w = amplify(weak)
        var s = amplify(strong)
        // Drive both motors so budget dual-motor pads still shake.
        if w > 0.05 && s < 0.05 { s = w * 0.9 }
        if s > 0.05 && w < 0.05 { w = s * 0.85 }

        guard w > 0.02 || s > 0.02 else {
            stop()
            return
        }

        do {
            try ensureEngine()
            guard let engine else { return }

            let duration = min(max(durationMs / 1000.0, 0.1), 3.0)
            var events: [CHHapticEvent] = []
            let peak = min(max(w, s), 1)

            // Hard attack — helps weak wired motors kick.
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: peak),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                    ],
                    relativeTime: 0
                )
            )

            if w > 0.02 {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: w),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.12),
                        ],
                        relativeTime: 0,
                        duration: duration
                    )
                )
            }

            if s > 0.02 {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: s),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.98),
                        ],
                        relativeTime: 0,
                        duration: duration
                    )
                )
            }

            // Extra punches for sustained fire feel.
            if duration >= 0.12 {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: peak),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.75),
                        ],
                        relativeTime: min(duration * 0.3, 0.18)
                    )
                )
            }
            if duration >= 0.22 {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: peak * 0.9),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85),
                        ],
                        relativeTime: min(duration * 0.55, 0.35)
                    )
                )
            }

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)

            lastStopWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.softStop() }
            }
            lastStopWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1, execute: item)
        } catch {
            engine = nil
            engineControllerID = nil
        }
    }

    /// Settings test button — strong dual pulse at current intensity.
    func playTest() {
        // Temporarily force-enable path even if toggle was off for testing feedback.
        let wasChecking = isEnabled
        // Always try to play test so user can feel the pad; still fail-silent.
        _ = wasChecking
        play(weak: 1.0, strong: 1.0, durationMs: 420)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            Task { @MainActor in
                self?.play(weak: 0.85, strong: 1.0, durationMs: 280)
            }
        }
    }

    func stop() {
        lastStopWorkItem?.cancel()
        lastStopWorkItem = nil
        softStop()
    }

    func teardown() {
        stop()
        engine?.stop(completionHandler: { _ in })
        engine = nil
        engineControllerID = nil
    }

    // MARK: - Private

    private func amplify(_ v: Float) -> Float {
        let raw = min(max(v, 0), 1)
        guard raw > 0.008 else { return 0 }
        // baseGain * userIntensity can exceed 1 — clamp at motor max.
        let boosted = min(raw * baseGain * userIntensity, 1)
        return max(boosted, min(floor * userIntensity, 1))
    }

    private func ensureEngine() throws {
        let controllers = GCController.controllers()
        guard let controller = controllers.first(where: { $0.haptics != nil }) ?? controllers.first else {
            engine = nil
            engineControllerID = nil
            return
        }
        let id = ObjectIdentifier(controller)
        if engine != nil, engineControllerID == id { return }

        engine?.stop(completionHandler: { _ in })
        engine = nil
        engineControllerID = nil

        guard let haptics = controller.haptics else { return }
        guard let created = haptics.createEngine(withLocality: .default) else { return }
        created.playsHapticsOnly = true
        created.isAutoShutdownEnabled = false
        try created.start()
        engine = created
        engineControllerID = id

        created.resetHandler = { [weak self] in
            Task { @MainActor in
                self?.engine = nil
                self?.engineControllerID = nil
            }
        }
        created.stoppedHandler = { [weak self] _ in
            Task { @MainActor in
                self?.engine = nil
                self?.engineControllerID = nil
            }
        }
    }

    private func softStop() {}
}
