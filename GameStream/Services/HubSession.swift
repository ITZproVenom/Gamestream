import Foundation
import Combine

@MainActor
final class HubState: ObservableObject {
    static let shared = HubState()
    @Published var showNativeHub: Bool = true
}

extension SessionStore {
    func openXboxCloud() {
        webURL = URL(string: "https://www.xbox.com/play")!
        isStreaming = false
        HubState.shared.showNativeHub = false
        requestedTab = .library
    }

    func openCatalogGame(_ game: CatalogGame) {
        HubState.shared.showNativeHub = false
        openGame(game.tracked)
    }

    func playCatalogGame(_ game: CatalogGame) {
        HubState.shared.showNativeHub = false
        playGame(game.tracked)
    }

    func returnToHub() {
        isStreaming = false
        HubState.shared.showNativeHub = true
        requestedTab = .library
    }
}
