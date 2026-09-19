import Foundation
import GameController
import CoreHaptics

/// Plays dual-motor style rumble on a connected physical controller while streaming.
///
/// Safety rules (crash isolation):
/// - No work at process launch or static init.
/// - Engine created lazily on first in-stream rumble request.
/// - Every failure is swallowed; rumble is best-effort only.
/// - Respects AppearanceStore.controllerHapticsEnabled (read via UserDefaults to avoid MainActor hops from JS bridge).
@MainActor
final class ControllerRumble {
    static let shared = ControllerRumble()

    private var engine: CHHapticEngine?
    private var engineControllerID: ObjectIdentifier?
    private var lastStopWorkItem: DispatchWorkItem?

    private init() {}

    /// Continuous dual-motor pulse. Intensities are 0...1 (weak = low-freq, strong = high-freq).
    func play(weak: Float, strong: Float, durationMs: Double) {
        guard isEnabled else { return }
        let w = clamp(weak)
        let s = clamp(strong)
        guard w > 0.01 || s > 0.01 else {
            stop()
            return
        }

        do {
            try ensureEngine()
            guard let engine else { return }

            let intensity = max(w, s)
            let sharpness = s >= w ? 0.85 : 0.25
            let duration = min(max(durationMs / 1000.0, 0.02), 2.5)

            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: 0,
                duration: duration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)

            lastStopWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.softStop() }
            }
            lastStopWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: item)
        } catch {
            // Fail silent — never crash the stream.
            engine = nil
            engineControllerID = nil
        }
    }

    func stop() {
        lastStopWorkItem?.cancel()
        lastStopWorkItem = nil
        softStop()
    }

    /// Tear down when leaving a stream so the next session starts clean.
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

    private func clamp(_ v: Float) -> Float {
        min(max(v, 0), 1)
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
        let created = haptics.createEngine(withLocality: .default)
        created.playsHapticsOnly = true
        created.isAutoShutdownEnabled = true
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

    private func softStop() {
        // Continuous events end on their own; nothing else required.
    }
}
