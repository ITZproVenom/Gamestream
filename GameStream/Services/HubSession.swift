import Foundation

extension SessionStore {
    func openXboxCloud() {
        webURL = URL(string: "https://www.xbox.com/play")!
        isStreaming = false
        showNativeHub = false
        requestedTab = .library
    }

    func openCatalogGame(_ game: CatalogGame) {
        openGame(game.tracked)
        showNativeHub = false
    }

    func playCatalogGame(_ game: CatalogGame) {
        playGame(game.tracked)
        showNativeHub = false
    }

    func returnToHub() {
        isStreaming = false
        showNativeHub = true
        requestedTab = .library
    }
}
