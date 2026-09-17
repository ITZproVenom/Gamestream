import Foundation

/// Intentionally empty. Custom/offline WAV embedding is disabled until
/// the launch-crash regression is proven fixed with system-sound SFX.
enum EmbeddedSounds {
    static let wavData: [String: Data] = [:]
}
