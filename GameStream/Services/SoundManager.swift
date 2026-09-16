import AudioToolbox
import AVFoundation

/// UI SFX. Never touch AVAudioSession / AVAudioPlayer / files during app startup.
/// First audio work happens only on an explicit play* call after launch.
enum SoundManager {
    private static var players: [String: AVAudioPlayer] = [:]
    private static var decoded: [String: Data] = [:]
    private static var categoryConfigured = false
    private static let lock = NSLock()

    private static var soundsEnabled: Bool {
        if UserDefaults.standard.object(forKey: "GameStream.uiSoundsEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "GameStream.uiSoundsEnabled")
    }

    static func playTap() { playBundled("tap", systemFallback: 1104) }
    static func playSuccess() { playBundled("ready", systemFallback: 1025) }
    static func playError() { playBundled("error", systemFallback: 1053) }
    static func playLaunch() {
        playBundled("launch", systemFallback: 1113)
        HapticManager.impact()
    }
    static func playReady() {
        playBundled("ready", systemFallback: 1114)
        HapticManager.success()
    }

    private static func playBundled(_ name: String, systemFallback: SystemSoundID) {
        guard soundsEnabled else { return }
        // Never query AVAudioSession.sharedInstance() just to decide mute — that
        // initializes the session. System sounds and ambient playback already
        // respect the Silent switch / mix-with-others.
        if playCustom(name) { return }
        AudioServicesPlaySystemSound(systemFallback)
    }

    @discardableResult
    private static func playCustom(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let existing = players[name] {
            existing.currentTime = 0
            return existing.play()
        }
        guard let data = soundData(name), !data.isEmpty else { return false }
        configureCategoryIfNeeded()
        guard let player = try? AVAudioPlayer(data: data) else { return false }
        player.prepareToPlay()
        players[name] = player
        return player.play()
    }

    /// Category only — never setActive. Activating the session at launch/play
    /// is what crashed sideloaded builds after the v1.5.0 audio work.
    private static func configureCategoryIfNeeded() {
        guard !categoryConfigured else { return }
        categoryConfigured = true
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers]
            )
        } catch {
            // Non-fatal: custom playback may still work; otherwise system sound.
        }
    }

    private static func soundData(_ name: String) -> Data? {
        if let cached = decoded[name], !cached.isEmpty { return cached }
        // Code-first source: tones baked into the binary. This is the ONLY
        // source present in the shipped (clean) bundle — no loose wav files.
        if let embedded = EmbeddedSounds.wavData[name], embedded.count > 44 {
            decoded[name] = embedded
            return embedded
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "wav"),
           let data = try? Data(contentsOf: url),
           data.count > 44 {
            decoded[name] = data
            return data
        }
        if let data = decodeB64File(name) {
            decoded[name] = data
            return data
        }
        loadEmbeddedIfNeeded()
        if let data = decoded[name], data.count > 44 { return data }
        return nil
    }

    private static func decodeB64File(_ name: String) -> Data? {
        let url = Bundle.main.url(forResource: name, withExtension: "wav.b64", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "wav.b64")
        guard let url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: trimmed), raw.count > 44 else { return nil }
        return raw
    }

    private static func loadEmbeddedIfNeeded() {
        let url = Bundle.main.url(forResource: "embedded", withExtension: "json", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: "embedded", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        for (key, b64) in map {
            if decoded[key] != nil { continue }
            let trimmed = b64.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 16,
                  let raw = Data(base64Encoded: trimmed),
                  raw.count > 44 else { continue }
            decoded[key] = raw
        }
    }
}
