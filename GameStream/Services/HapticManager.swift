import UIKit

/// Crash-free haptics baseline.
/// Device Taptic Engine only. No CoreHaptics, no GameController,
/// no engines created at launch, no hardware capability probes.
/// Generators are created on first explicit play() and every call is
/// wrapped so a missing Taptic Engine cannot take the app down.
enum HapticManager {
    enum Style {
        case light, medium, heavy, success, error
    }

    static func play(_ style: Style = .light) {
        playDevice(style)
    }

    static func tap() { play(.light) }
    static func impact() { play(.medium) }
    static func success() { play(.success) }
    static func error() { play(.error) }

    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static var notificationGenerator: UINotificationFeedbackGenerator?

    private static func playDevice(_ style: Style) {
        switch style {
        case .light:
            deviceImpact(.light)
        case .medium:
            deviceImpact(.medium)
        case .heavy:
            deviceImpact(.heavy)
        case .success:
            notification().notificationOccurred(.success)
        case .error:
            notification().notificationOccurred(.error)
        }
    }

    private static func notification() -> UINotificationFeedbackGenerator {
        if let existing = notificationGenerator { return existing }
        let made = UINotificationFeedbackGenerator()
        notificationGenerator = made
        return made
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

    /// Kept so existing call sites compile. Always false in the
    /// crash-free baseline (controller rumble is disabled).
    @discardableResult
    static func controllerConnected() -> Bool {
        false
    }
}
