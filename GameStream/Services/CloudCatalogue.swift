import Foundation

/// Reads the cloud catalogue from Xbox's own site.
///
/// The app's catalogue comes from the Game Pass list, which lags and leaves
/// out anything outside the subscription - so a title that launched
/// yesterday is missing from it, and a title that is missing from it cannot
/// be started from the app at all.
///
/// Xbox's own pages list what the cloud can play, including the free
/// titles and the new arrivals. Reading that list means the app shows the
/// same games the website does, rather than a month-old subscription feed.
@MainActor
final class CloudCatalogue: ObservableObject {
    static let shared = CloudCatalogue()

    /// The titles the site offers, keyed by product id.
    @Published private(set) var titles: [String: Game] = [:]
    @Published private(set) var fetchedAt: Date?

    private init() {}

    /// Takes the titles the site's pages listed and puts them in the app's
    /// catalogue.
    func absorb(_ games: [Game]) {
        guard !games.isEmpty else { return }
        var added = 0
        for game in games {
            let key = game.id.uppercased()
            if titles[key] == nil { added += 1 }
            titles[key] = game
        }
        fetchedAt = Date()
        AppLog.shared.info("catalog", "the site lists \(titles.count) cloud titles"
                           + (added > 0 ? " (\(added) new)" : ""))
        Catalog.shared.addCloudSiteTitles(games)
    }
}
