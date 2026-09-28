import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Puts the library into iOS search, so a game can be started from the home
/// screen without opening the app and finding it first.
enum SpotlightIndex {
    static let domain = "com.gamestream.library"

    static func update(with games: [Game]) {
        let items = games.prefix(400).map { game -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.content)
            attributes.title = game.title
            attributes.contentDescription = game.tagline.isEmpty
                ? "\(game.genre) on Xbox Cloud Gaming"
                : game.tagline
            attributes.keywords = [game.genre, "Xbox", "cloud", "GameStream"]
            attributes.thumbnailURL = nil
            let item = CSSearchableItem(uniqueIdentifier: game.id,
                                        domainIdentifier: domain,
                                        attributeSet: attributes)
            return item
        }
        CSSearchableIndex.default().indexSearchableItems(Array(items)) { error in
            if let error {
                AppLog.shared.debug("spotlight", "indexing failed: \(error.localizedDescription)")
            } else {
                AppLog.shared.debug("spotlight", "indexed \(items.count) games")
            }
        }
    }

    static func clear() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }
}
