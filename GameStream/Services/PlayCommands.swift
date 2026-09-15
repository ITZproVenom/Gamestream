import Foundation

extension SessionStore {
    /// Single Play path: hide GameHub and load the Xbox Cloud *launch* URL only.
    /// Never bounce through /play/games first — that race is what broke /play.
    func playGame(_ game: TrackedGame) {
        guard let url = game.launchURL else { return }
        pendingJavaScript = nil
        HubState.shared.showNativeHub = false
        offerPlayNext = false
        requestedTab = .library
        currentGame = TrackedGame(
            id: game.id,
            slug: game.slug,
            title: game.title,
            lastSeen: Date(),
            isFavorite: isFavorite(game.id)
        )
        if webURL != url {
            webURL = url
        }
        isStreaming = true
    }

    func playCurrent() {
        guard let game = currentGame else { return }
        playGame(game)
    }

    var continueGame: TrackedGame? {
        recents.first
    }
}
