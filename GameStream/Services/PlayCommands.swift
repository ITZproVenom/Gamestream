import Foundation

extension SessionStore {
    /// Jump straight into Xbox Cloud launch instead of the catalog page.
    func playGame(_ game: TrackedGame) {
        openGame(game)
        if let url = game.launchURL {
            webURL = url
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
