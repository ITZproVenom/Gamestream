import Foundation
import Combine

@MainActor
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    @Published private(set) var collections: [GameCollection] = []

    private let storageKey = "GameStream.collections.v1"

    init() {
        collections = Self.load(key: storageKey)
    }

    @discardableResult
    func create(named rawName: String) -> GameCollection? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = collections.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let collection = GameCollection(id: UUID().uuidString, name: name, gameIDs: [], createdAt: Date())
        collections.insert(collection, at: 0)
        if collections.count > 12 {
            collections = Array(collections.prefix(12))
        }
        persist()
        return collection
    }

    func delete(_ id: String) {
        collections.removeAll { $0.id == id }
        persist()
    }

    func toggle(game: TrackedGame, inCollection id: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        if collections[index].gameIDs.contains(game.id) {
            collections[index].gameIDs.removeAll { $0 == game.id }
        } else {
            collections[index].gameIDs.insert(game.id, at: 0)
            if collections[index].gameIDs.count > 24 {
                collections[index].gameIDs = Array(collections[index].gameIDs.prefix(24))
            }
        }
        persist()
    }

    func contains(_ gameID: String, inCollection id: String) -> Bool {
        collections.first(where: { $0.id == id })?.gameIDs.contains(gameID) == true
    }

    func games(inCollection id: String, favorites: [TrackedGame], recents: [TrackedGame]) -> [CatalogGame] {
        guard let collection = collections.first(where: { $0.id == id }) else { return [] }
        return collection.gameIDs.map { rawID in
            if let catalog = GameCatalog.game(id: rawID) { return catalog }
            if let tracked = favorites.first(where: { $0.id == rawID }) ?? recents.first(where: { $0.id == rawID }) {
                return GameCatalog.catalog(from: tracked)
            }
            return CatalogGame(
                id: rawID,
                slug: rawID.lowercased(),
                title: rawID,
                tagline: "Xbox Cloud Gaming",
                genre: "Cloud",
                provider: "Xbox Cloud",
                featured: false,
                accent: 0x4361EE
            )
        }
    }

    func clear() {
        collections = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func load(key: String) -> [GameCollection] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([GameCollection].self, from: data)) ?? []
    }
}
