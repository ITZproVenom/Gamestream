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
        returnToHub()
    }

    func openCatalogGame(_ game: CatalogGame) {
        HubState.shared.showNativeHub = true
        offerPlayNext = false
        requestedTab = .home
        noteOpenedGame(game.tracked)
    }

    func playCatalogGame(_ game: CatalogGame) {
        playGame(game.tracked)
    }

    func openCloudSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSearchDraft(trimmed)
        SessionStore.rememberSearch(trimmed)
        // Analytics: never include the raw query text.
        DiagnosticsStore.shared.record(
            event: "search_started",
            feature: "search",
            properties: ["channel": "xbox_cloud", "query_len": String(trimmed.count)]
        )
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        guard let url = URL(string: "https://www.xbox.com/play/search/\(encoded)") else {
            DiagnosticsStore.shared.record(
                event: "search_failed",
                feature: "search",
                properties: ["reason": "bad_url"],
                errorCategory: "bad_url"
            )
            requestedTab = .search
            return
        }
        pendingJavaScript = nil
        HubState.shared.showNativeHub = false
        offerPlayNext = false
        ensureDefaultStreamQualityPrefs()
        isStreaming = true
        webURL = url
        requestedTab = .home
        DiagnosticsStore.shared.record(
            event: "search_success",
            feature: "search",
            properties: ["channel": "xbox_cloud"]
        )
    }

    func returnToHub() {
        PlayActivityStore.shared.end()
        pendingJavaScript = nil
        isStreaming = false
        webURL = Self.idleWebURL
        HubState.shared.showNativeHub = true
        requestedTab = .home
    }

    func exitStreamToHub() {
        PlayActivityStore.shared.end()
        pendingJavaScript = nil
        let hasNext = nextQueuedGame != nil
        webURL = Self.idleWebURL
        isStreaming = false
        offerPlayNext = hasNext
        HubState.shared.showNativeHub = true
        requestedTab = .home
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
