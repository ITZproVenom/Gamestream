/// Crash-isolation haptics.
/// Completely inert. No UIKit generators, CoreHaptics, or GameController.
enum HapticManager {
    enum Style {
        case light, medium, heavy, success, error
    }

    static func play(_ style: Style = .light) {}
    static func tap() {}
    static func impact() {}
    static func success() {}
    static func error() {}

    @discardableResult
    static func controllerConnected() -> Bool { false }
}
