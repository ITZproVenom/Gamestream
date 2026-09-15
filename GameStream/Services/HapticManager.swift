import UIKit
import GameController
import CoreHaptics

/// Dual-path haptics: Taptic Engine + controller haptics when a gamepad is connected.
/// Nothing here runs at process start. GameController / CoreHaptics are touched
/// only from an explicit play() after launch. All failures are swallowed.
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

    private static func playDevice(_ style: Style) {
        switch style {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private static func playController(_ style: Style) {
        // Do not start CHHapticEngine / scan controllers unless one is already present.
        let controllers = GCController.controllers()
        guard !controllers.isEmpty else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        for controller in controllers {
            guard let deviceHaptics = controller.haptics else { continue }
            for locality in [GCHapticsLocality.default, .handles] {
                guard let engine = deviceHaptics.createEngine(withLocality: locality) else { continue }
                do {
                    try engine.start()
                    let pattern = try Self.pattern(for: style)
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: 0)
                } catch {
                    continue
                }
            }
        }
    }

    private static func pattern(for style: Style) throws -> CHHapticPattern {
        let intensity: Float
        let sharpness: Float
        let duration: TimeInterval

        switch style {
        case .light:
            intensity = 0.35; sharpness = 0.55; duration = 0.04
        case .medium:
            intensity = 0.55; sharpness = 0.45; duration = 0.06
        case .heavy:
            intensity = 0.85; sharpness = 0.35; duration = 0.09
        case .success:
            intensity = 0.5; sharpness = 0.7; duration = 0.05
        case .error:
            intensity = 0.7; sharpness = 0.2; duration = 0.12
        }

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0,
            duration: duration
        )

        if style == .success {
            let second = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85)
                ],
                relativeTime: 0.08,
                duration: 0.04
            )
            return try CHHapticPattern(events: [event, second], parameters: [])
        }

        if style == .error {
            let second = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
                ],
                relativeTime: 0.02,
                duration: 0.1
            )
            return try CHHapticPattern(events: [event, second], parameters: [])
        }

        return try CHHapticPattern(events: [event], parameters: [])
    }
}
