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

    /// Native GameHub is the catalog. Do not load xbox.com as a screen.
    func openXboxCloud() {
        returnToHub()
    }

    func openCatalogGame(_ game: CatalogGame) {
        HubState.shared.showNativeHub = true
        offerPlayNext = false
        requestedTab = .library
        noteOpenedGame(game.tracked)
    }

    func playCatalogGame(_ game: CatalogGame) {
        playGame(game.tracked)
    }

    /// Opens the Xbox Cloud search page in the stream player so "Search Xbox Cloud"
    /// is a real navigation, not a no-op tab switch.
    func openCloudSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSearchDraft(trimmed)
        SessionStore.rememberSearch(trimmed)
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        guard let url = URL(string: "https://www.xbox.com/play/search/\(encoded)") else {
            requestedTab = .search
            return
        }
        pendingJavaScript = nil
        HubState.shared.showNativeHub = false
        offerPlayNext = false
        // Keep currentGame if any; search is not a launch.
        ensureDefaultStreamQualityPrefs()
        isStreaming = true
        webURL = url
        requestedTab = .library
    }

    func returnToHub() {
        PlayActivityStore.shared.end()
        pendingJavaScript = nil
        isStreaming = false
        webURL = Self.idleWebURL
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

    fileprivate func noteOpenedGame(_ game: TrackedGame) {
        currentGame = TrackedGame(
            id: game.id,
            slug: game.slug,
            title: game.title,
            lastSeen: Date(),
            isFavorite: isFavorite(game.id)
        )
    }
}
