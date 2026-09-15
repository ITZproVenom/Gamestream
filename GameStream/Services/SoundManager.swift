import AudioToolbox
import AVFoundation
import UIKit

enum SoundManager {
    private static var players: [String: AVAudioPlayer] = [:]
    private static let sessionConfigured: Bool = {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
        return true
    }()

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
        playBundled("tap", systemFallback: 1104)
    }

    static func playSuccess() {
        playBundled("ready", systemFallback: 1025)
    }

    static func playError() {
        playBundled("error", systemFallback: 1053)
    }

    static func playLaunch() {
        playBundled("launch", systemFallback: 1113)
        HapticManager.impact()
    }

    static func playReady() {
        playBundled("ready", systemFallback: 1114)
        HapticManager.success()
    }

    private static func playBundled(_ name: String, systemFallback: SystemSoundID) {
        guard soundsEnabled, !isMuted else { return }
        _ = sessionConfigured

        if let player = cachedPlayer(name) {
            player.currentTime = 0
            player.play()
            return
        }
        AudioServicesPlaySystemSound(systemFallback)
    }

    private static func cachedPlayer(_ name: String) -> AVAudioPlayer? {
        if let existing = players[name] { return existing }
        let url =
            Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
        guard let url,
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[name] = player
        return player
    }
}
