import AudioToolbox

enum SoundManager {
    // System sound IDs — built into iOS, no audio files needed.
    private static let tapSound: SystemSoundID = 1104
    private static let successSound: SystemSoundID = 1025

    static func playTap() {
        AudioServicesPlaySystemSound(tapSound)
    }

    static func playSuccess() {
        AudioServicesPlaySystemSound(successSound)
    }
}
