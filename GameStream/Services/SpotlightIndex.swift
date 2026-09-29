import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Puts the library into iOS search, so a game can be started from the home
/// screen without opening the app and finding it first.
enum SpotlightIndex {
    static let domain = "com.gamestream.library"

    /// The identifiers written last time, so the ones that have since gone
    /// can be taken out again.
    private static let indexedKey = "spotlight.indexedIdentifiers"

    static func update(with games: [Game]) {
        let kept = Array(games.prefix(400))
        removeDeparted(keeping: kept)

        let items = kept.map { game -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.content)
            attributes.title = game.title
            attributes.contentDescription = game.tagline.isEmpty
                ? "\(game.genre) on Xbox Cloud Gaming"
                : game.tagline
            attributes.keywords = [game.genre, "Xbox", "cloud", "GameStream"]
            let item = CSSearchableItem(uniqueIdentifier: game.id,
                                        domainIdentifier: domain,
                                        attributeSet: attributes)
            return item
        }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                AppLog.shared.debug("spotlight", "indexing failed: \(error.localizedDescription)")
            } else {
                AppLog.shared.debug("spotlight", "indexed \(items.count) games")
            }
        }
    }

    /// Game Pass removes titles every month. Indexing only ever added, so a
    /// game that had left the service still turned up in iOS search and
    /// opening it led to a page for something no longer streamable.
    private static func removeDeparted(keeping games: [Game]) {
        let defaults = UserDefaults.standard
        let current = Set(games.map(\.id))
        let previous = Set(defaults.stringArray(forKey: indexedKey) ?? [])
        defaults.set(Array(current), forKey: indexedKey)

        let departed = Array(previous.subtracting(current))
        guard !departed.isEmpty else { return }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: departed) { error in
            if let error {
                AppLog.shared.debug("spotlight",
                                    "could not remove \(departed.count): "
                                    + error.localizedDescription)
            } else {
                AppLog.shared.debug("spotlight", "removed \(departed.count) delisted games")
            }
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: indexedKey)
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }
}
