import Foundation
import Combine

@MainActor
final class HubState: ObservableObject {
    static let shared = HubState()
    @Published var showNativeHub: Bool = true
}

extension SessionStore {
    static let idleWebURL = URL(string: "about:blank")!
    static let xboxHomeURL = URL(string: "https://www.xbox.com/play")!

    func openXboxCloud() {
        PlayActivityStore.shared.end()
        pendingJavaScript = nil
        webURL = Self.xboxHomeURL
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
        playGame(game.tracked)
    }

    func returnToHub() {
        PlayActivityStore.shared.end()
        pendingJavaScript = nil
        isStreaming = false
        // Unload the Xbox site while GameHub is the UI so the website is not the app.
        if webURL.host?.contains("xbox.com") == true {
            webURL = Self.idleWebURL
        }
        HubState.shared.showNativeHub = true
        requestedTab = .library
    }

    func exitStreamToHub() {
        PlayActivityStore.shared.end()
        pendingJavaScript = nil
        let hasNext = nextQueuedGame != nil
        webURL = Self.idleWebURL
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
