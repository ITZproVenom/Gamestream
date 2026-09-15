import AudioToolbox
import AVFoundation

enum SoundManager {
    private static let tapSound: SystemSoundID = 1104
    private static let successSound: SystemSoundID = 1025
    private static let errorSound: SystemSoundID = 1053
    /// Soft begin tone when Play is tapped.
    private static let launchSound: SystemSoundID = 1113
    /// Confirm when stream shell is ready.
    private static let readySound: SystemSoundID = 1114

    private static var soundsEnabled: Bool {
        if UserDefaults.standard.object(forKey: "GameStream.uiSoundsEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "GameStream.uiSoundsEnabled")
    }

    private static var isMuted: Bool {
        AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    static func playTap() {
        guard soundsEnabled, !isMuted else { return }
        AudioServicesPlaySystemSound(tapSound)
    }

    static func playSuccess() {
        guard soundsEnabled, !isMuted else { return }
        AudioServicesPlaySystemSound(successSound)
    }

    static func playError() {
        guard soundsEnabled, !isMuted else { return }
        AudioServicesPlaySystemSound(errorSound)
    }

    static func playLaunch() {
        guard soundsEnabled, !isMuted else { return }
        AudioServicesPlaySystemSound(launchSound)
    }

    static func playReady() {
        guard soundsEnabled, !isMuted else { return }
        AudioServicesPlaySystemSound(readySound)
    }
}
