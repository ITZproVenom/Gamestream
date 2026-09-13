import Foundation

extension SessionStore {
    /// Jump straight into Xbox Cloud launch instead of the catalog page.
    func playGame(_ game: TrackedGame) {
        guard let url = game.launchURL else { return }
        webURL = url
        isStreaming = false
        requestedTab = .library
        noteGame(id: game.id, slug: game.slug, title: game.title, markRecent: true)
    }

    func playCurrent() {
        guard let game = currentGame else { return }
        playGame(game)
    }

    var continueGame: TrackedGame? {
        recents.first
    }
}
