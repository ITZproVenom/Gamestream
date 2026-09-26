import Foundation
import GameController
import CoreHaptics

@MainActor
final class ControllerRumble {
    static let shared = ControllerRumble()

    private enum Defaults {
        static let enabled = "GameStream.controllerHapticsEnabled"
        static let intensity = "GameStream.controllerRumbleIntensity"
    }

    private var leftEngine: CHHapticEngine?
    private var rightEngine: CHHapticEngine?
    private var handlesEngine: CHHapticEngine?
    private var defaultEngine: CHHapticEngine?
    private var controllerID: ObjectIdentifier?
    private var leftAvailable = false
    private var rightAvailable = false
    private var handlesAvailable = false
    private var defaultAvailable = false
    private var generation = 0

    private init() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.invalidateEngines() }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.invalidateEngines() }
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Defaults.enabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Defaults.enabled)
    }

    var connectedControllerName: String? { activeController()?.vendorName }

    var supportsRumble: Bool { activeController()?.haptics != nil }

    func play(weak: Float, strong: Float, durationMs: Double, force: Bool = false) {
        guard force || isEnabled else { return }
        let left = scale(weak)
        let right = scale(strong)
        guard left > 0 || right > 0, prepare() else { return }
        let duration = min(max(durationMs / 1000, 0.025), 2.5)
        do {
            var played = false
            if leftAvailable, let engine = leftEngine { played = try play(engine, intensity: left, duration: duration) || played }
            if rightAvailable, let engine = rightEngine { played = try play(engine, intensity: right, duration: duration) || played }
            if !played {
                let intensity = max(left, right)
                if handlesAvailable, let engine = handlesEngine { played = try play(engine, intensity: intensity, duration: duration) || played }
                if !played, defaultAvailable, let engine = defaultEngine { _ = try play(engine, intensity: intensity, duration: duration) }
            }
        } catch {
            invalidateEngines()
        }
    }

    func testLeft() { testChannel(left: true, right: false) }
    func testRight() { testChannel(left: false, right: true) }

    func playTest() {
        testLeft()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in Task { @MainActor in self?.testRight() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in Task { @MainActor in self?.play(weak: 1, strong: 1, durationMs: 350, force: true) } }
    }

    func teardown() { invalidateEngines() }

    private func activeController() -> GCController? {
        let controllers = GCController.controllers()
        if let current = GCController.current, current.haptics != nil { return current }
        return controllers.first(where: { $0.haptics != nil })
    }

    private func prepare() -> Bool {
        guard let controller = activeController(), let haptics = controller.haptics else {
            invalidateEngines()
            return false
        }
        let id = ObjectIdentifier(controller)
        if controllerID == id, leftEngine != nil || rightEngine != nil || handlesEngine != nil || defaultEngine != nil { return true }
        invalidateEngines()
        let localities = haptics.supportedLocalities
        controllerID = id
        do {
            if localities.contains(.leftHandle), let e = haptics.createEngine(withLocality: .leftHandle) { try start(e); leftEngine = e; leftAvailable = true }
            if localities.contains(.rightHandle), let e = haptics.createEngine(withLocality: .rightHandle) { try start(e); rightEngine = e; rightAvailable = true }
            if localities.contains(.handles), let e = haptics.createEngine(withLocality: .handles) { try start(e); handlesEngine = e; handlesAvailable = true }
            if localities.contains(.default), let e = haptics.createEngine(withLocality: .default) { try start(e); defaultEngine = e; defaultAvailable = true }
            return leftAvailable || rightAvailable || handlesAvailable || defaultAvailable
        } catch {
            invalidateEngines()
            return false
        }
    }

    private func start(_ engine: CHHapticEngine) throws {
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        let g = generation
        engine.resetHandler = { [weak self] in Task { @MainActor in if self?.generation == g { self?.invalidateEngines() } } }
        engine.stoppedHandler = { [weak self] _ in Task { @MainActor in if self?.generation == g { self?.invalidateEngines() } } }
        try engine.start()
    }

    private func testChannel(left: Bool, right: Bool) {
        guard prepare() else { return }
        do {
            if left, leftAvailable, let e = leftEngine { _ = try play(e, intensity: scale(1), duration: 0.45) }
            if right, rightAvailable, let e = rightEngine { _ = try play(e, intensity: scale(1), duration: 0.45) }
        } catch { invalidateEngines() }
    }

    private func play(_ engine: CHHapticEngine, intensity: Float, duration: TimeInterval) throws -> Bool {
        guard intensity > 0.005 else { return false }
        let pattern = try CHHapticPattern(events: [CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(max(intensity, 0), 1)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
        ], relativeTime: 0, duration: duration)], parameters: [])
        let player = try engine.makeAdvancedPlayer(with: pattern)
        try player.start(atTime: 0)
        return true
    }

    private func scale(_ value: Float) -> Float {
        let raw = min(max(value, 0), 1)
        guard raw > 0.005 else { return 0 }
        let stored = UserDefaults.standard.object(forKey: Defaults.intensity) as? Double
        let intensity = min(max(Float(stored ?? 1.6), 0.5), 3)
        return min(max(raw * 2.2 * intensity, 0.08), 1)
    }

    private func invalidateEngines() {
        generation &+= 1
        leftEngine?.stop(completionHandler: nil)
        rightEngine?.stop(completionHandler: nil)
        handlesEngine?.stop(completionHandler: nil)
        defaultEngine?.stop(completionHandler: nil)
        leftEngine = nil; rightEngine = nil; handlesEngine = nil; defaultEngine = nil
        leftAvailable = false; rightAvailable = false; handlesAvailable = false; defaultAvailable = false
        controllerID = nil
    }
}
