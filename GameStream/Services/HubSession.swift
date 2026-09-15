import Foundation
import Combine

@MainActor
final class HubState: ObservableObject {
    static let shared = HubState()
    @Published var showNativeHub: Bool = true
}

extension SessionStore {
    func openXboxCloud() {
        PlayActivityStore.shared.end()
        webURL = URL(string: "https://www.xbox.com/play")!
        isStreaming = false
        offerPlayNext = false
        HubState.shared.showNativeHub = false
        requestedTab = .library
    }

    func openCatalogGame(_ game: CatalogGame) {
        HubState.shared.showNativeHub = false
        offerPlayNext = false
        openGame(game.tracked)
    }

    func playCatalogGame(_ game: CatalogGame) {
        HubState.shared.showNativeHub = false
        offerPlayNext = false
        playGame(game.tracked)
    }

    func returnToHub() {
        PlayActivityStore.shared.end()
        isStreaming = false
        HubState.shared.showNativeHub = true
        requestedTab = .library
    }

    func exitStreamToHub() {
        PlayActivityStore.shared.end()
        let hasNext = nextQueuedGame != nil
        webURL = URL(string: "https://www.xbox.com/play")!
        isStreaming = false
        offerPlayNext = hasNext
        HubState.shared.showNativeHub = true
        requestedTab = .library
    }

    func playNextFromStream() {
        PlayActivityStore.shared.end()
        offerPlayNext = false
        if playNextQueued() { return }
        exitStreamToHub()
    }
}
