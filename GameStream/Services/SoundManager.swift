/// Crash-isolation SFX.
/// Completely inert. Audio must never be able to crash or block launch.
enum SoundManager {
    static func playTap() {}
    static func playSuccess() {}
    static func playError() {}
    static func playLaunch() {}
    static func playReady() {}
}
