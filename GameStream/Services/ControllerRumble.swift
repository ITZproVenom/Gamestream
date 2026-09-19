import Foundation
import GameController
import CoreHaptics

/// Plays dual-motor style rumble on a connected physical controller while streaming.
///
/// Safety rules (crash isolation):
/// - No work at process launch or static init.
/// - Engine created lazily on first in-stream rumble request.
/// - Every failure is swallowed; rumble is best-effort only.
/// - Respects AppearanceStore.controllerHapticsEnabled.
///
/// Intensity is intentionally aggressive: many wired / budget pads feel weak at
/// 1:1 game magnitudes, so we boost, floor, and layer events to drive motors harder.
@MainActor
final class ControllerRumble {
    static let shared = ControllerRumble()

    /// Software gain on top of game magnitudes (clamped to 1.0 after boost).
    private let gain: Float = 2.4
    /// Anything the game reports above this is treated as “at least this strong”.
    private let floor: Float = 0.55
    /// Extra transient punch at the start of each pulse.
    private let attackBoost: Float = 1.0

    private var engine: CHHapticEngine?
    private var engineControllerID: ObjectIdentifier?
    private var lastStopWorkItem: DispatchWorkItem?

    private init() {}

    /// Continuous dual-motor pulse. Intensities are 0...1 (weak = low-freq, strong = high-freq).
    func play(weak: Float, strong: Float, durationMs: Double) {
        guard isEnabled else { return }

        var w = amplify(weak)
        var s = amplify(strong)
        // If only one motor is driven, push both so cheap dual-motor pads still shake.
        if w > 0.05 && s < 0.05 { s = w * 0.85 }
        if s > 0.05 && w < 0.05 { w = s * 0.75 }

        guard w > 0.02 || s > 0.02 else {
            stop()
            return
        }

        do {
            try ensureEngine()
            guard let engine else { return }

            // Slightly longer than requested so weak motors have time to spin up.
            let duration = min(max(durationMs / 1000.0, 0.08), 3.0)
            var events: [CHHapticEvent] = []

            // Hard attack transient — helps weak wired motors “kick”.
            let peak = max(w, s)
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: min(peak * attackBoost, 1)),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                    ],
                    relativeTime: 0
                )
            )

            // Low-frequency continuous (weak / left motor feel).
            if w > 0.02 {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: w),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
                        ],
                        relativeTime: 0,
                        duration: duration
                    )
                )
            }

            // High-frequency continuous (strong / right motor feel).
            if s > 0.02 {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: s),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95),
                        ],
                        relativeTime: 0,
                        duration: duration
                    )
                )
            }

            // Second mid-pulse transient for sustained gunfire-style feedback.
            if duration >= 0.12 {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: peak),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
                        ],
                        relativeTime: min(duration * 0.35, 0.2)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.08, execute: item)
        } catch {
            engine = nil
            engineControllerID = nil
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

    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: "GameStream.controllerHapticsEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "GameStream.controllerHapticsEnabled")
    }

    /// Boost + floor so quiet game events still hit hard on weak wired pads.
    private func amplify(_ v: Float) -> Float {
        let raw = min(max(v, 0), 1)
        guard raw > 0.01 else { return 0 }
        let boosted = min(raw * gain, 1)
        return max(boosted, floor)
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
        // Keep the engine alive between rapid fire pulses so motors don’t spin down.
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
