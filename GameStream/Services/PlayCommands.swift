import Foundation

extension SessionStore {
    /// Single Play path: hide GameHub and load the Xbox Cloud *launch* URL only.
    /// Never bounce through /play/games first — that race is what broke /play.
    func playGame(_ game: TrackedGame) {
        pendingJavaScript = nil
        HubState.shared.showNativeHub = false
        offerPlayNext = false
        requestedTab = .library
        noteTrackedGame(game, markRecent: true)
        guard let url = game.launchURL else { return }
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
