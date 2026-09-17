import AudioToolbox

/// Crash-free UI SFX baseline.
/// System sounds only. No AVAudioSession, AVAudioPlayer, bundle I/O,
/// Base64 decode, or haptic side effects. Failures are impossible:
/// AudioServicesPlaySystemSound is fire-and-forget.
enum SoundManager {
    private static let tapSound: SystemSoundID = 1104
    private static let successSound: SystemSoundID = 1025
    private static let errorSound: SystemSoundID = 1053
    private static let launchSound: SystemSoundID = 1113
    private static let readySound: SystemSoundID = 1114

    private static var soundsEnabled: Bool {
        if UserDefaults.standard.object(forKey: "GameStream.uiSoundsEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "GameStream.uiSoundsEnabled")
    }

    static func playTap() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(tapSound)
    }

    static func playSuccess() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(successSound)
    }

    static func playError() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(errorSound)
    }

    static func playLaunch() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(launchSound)
    }

    static func playReady() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(readySound)
    }
}
