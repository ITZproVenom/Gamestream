import Foundation

extension SessionStore {
    /// Single Play path: establish the authenticated xbox.com session on the cloud
    /// home page first, then StreamPlayerView advances to the game *launch* page
    /// once xbox.com/play finishes without bouncing to a login host.
    func playGame(_ game: TrackedGame) {
        guard game.launchURL != nil else { return }
        SoundManager.playLaunch()
        pendingJavaScript = nil
        HubState.shared.showNativeHub = false
        offerPlayNext = false
        RemoteImageLoader.shared.clear()
        requestedTab = .library
        currentGame = TrackedGame(
            id: game.id,
            slug: game.slug,
            title: game.title,
            lastSeen: Date(),
            isFavorite: isFavorite(game.id)
        )
        // Seed Better xCloud quality prefs before the launch page loads.
        ensureDefaultStreamQualityPrefs()
        pendingJavaScript = Self.betterXCloudPrefsJS(Self.storedBetterXCloudPrefs(), reloadIfXbox: false)
        // Show StreamPlayerView first, then land on the authenticated cloud home.
        // The WebView shares the sign-in cookie store, so xbox.com/play either
        // renders signed-in or redirects to login.live.com where the user can
        // sign in directly — StreamPlayerView then advances to the launch URL.
        isStreaming = true
        if webURL != MicrosoftAuth.playURL {
            webURL = MicrosoftAuth.playURL
        }
    }

    /// Defaults tuned for readable mid-range detail (enemies, UI text) without a bitrate *cap*.
    func ensureDefaultStreamQualityPrefs() {
        var map = Self.storedBetterXCloudPrefs()
        var changed = false
        func setDefault(_ key: String, _ value: String) {
            if map[key] == nil {
                map[key] = value
                changed = true
            }
        }
        // Unlimited max bitrate (0 = no artificial ceiling in BX)
        setDefault("stream.video.maxBitrate", "0")
        // Client-side clarity boost (USM) — this is the upscaling/sharpen path
        setDefault("video.processing", "usm")
        setDefault("video.processing.sharpness", "5")
        setDefault("video.processing.mode", "quality")
        // Prefer high H.264 profile when the device supports it
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
