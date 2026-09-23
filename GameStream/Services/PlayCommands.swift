import Foundation

extension SessionStore {
    /// Single Play path: load the game's launch URL directly into the player.
    func playGame(_ game: TrackedGame) {
        guard let url = game.launchURL else { return }
        SoundManager.playLaunch()
        pendingJavaScript = nil
        HubState.shared.showNativeHub = false
        offerPlayNext = false
        RemoteImageLoader.shared.clear()
        requestedTab = .home
        currentGame = TrackedGame(
            id: game.id,
            slug: game.slug,
            title: game.title,
            lastSeen: Date(),
            isFavorite: isFavorite(game.id)
        )
        ensureDefaultStreamQualityPrefs()
        pendingJavaScript = Self.betterXCloudPrefsJS(Self.storedBetterXCloudPrefs(), reloadIfXbox: false)
        isStreaming = true
        if webURL != url {
            webURL = url
        }
    }

    func ensureDefaultStreamQualityPrefs() {
        var map = Self.storedBetterXCloudPrefs()
        var changed = false
        func setDefault(_ key: String, _ value: String) {
            if map[key] == nil {
                map[key] = value
                changed = true
            }
        }
        setDefault("stream.video.maxBitrate", "0")
        setDefault("video.processing", "usm")
        setDefault("video.processing.sharpness", "5")
        setDefault("video.processing.mode", "quality")
        setDefault("stream.video.codecProfile", "high")
        if changed {
            UserDefaults.standard.set(map, forKey: "BetterXCloud.prefs.v1")
        }
        if UserDefaults.standard.string(forKey: "GameStream.streamClarity") == nil {
            UserDefaults.standard.set("Unsharp", forKey: "GameStream.streamClarity")
        }
        if UserDefaults.standard.object(forKey: "GameStream.streamSharpness") == nil {
            UserDefaults.standard.set(5.0, forKey: "GameStream.streamSharpness")
        }
        if UserDefaults.standard.string(forKey: "GameStream.streamClarityMode") == nil {
            UserDefaults.standard.set("Quality", forKey: "GameStream.streamClarityMode")
        }
        if UserDefaults.standard.string(forKey: "GameStream.streamCodecProfile") == nil {
            UserDefaults.standard.set("High", forKey: "GameStream.streamCodecProfile")
        }
    }

    func playCurrent() {
        guard let game = currentGame else { return }
        playGame(game)
    }

    var continueGame: TrackedGame? {
        recents.first
    }
}
