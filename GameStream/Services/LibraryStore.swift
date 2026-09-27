import Foundation
import Combine

/// Everything the user has collected: favourites, history, queue, lists.
///
/// Each entry stores the whole `Game`, not just an identifier. That is the
/// difference from 1.x, where a favourite disappeared from the interface
/// whenever today's catalog request happened not to include it.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var favorites: [Game] = []
    @Published private(set) var recents: [Game] = []
    @Published private(set) var queue: [Game] = []
    @Published private(set) var lists: [GameList] = []
    @Published private(set) var activity: [PlayRecord] = []

    private enum Key {
        static let favorites = "library.favorites.v1"
        static let recents = "library.recents.v1"
        static let queue = "library.queue.v1"
        static let lists = "library.lists.v1"
        static let activity = "library.activity.v1"
    }

    private static let recentsLimit = 30
    private static let activityLimit = 300

    private init() {
        favorites = Self.load([Game].self, Key.favorites) ?? []
        recents = Self.load([Game].self, Key.recents) ?? []
        queue = Self.load([Game].self, Key.queue) ?? []
        lists = Self.load([GameList].self, Key.lists) ?? []
        activity = Self.load([PlayRecord].self, Key.activity) ?? []
    }

    // MARK: - Favourites

    func isFavorite(_ game: Game) -> Bool {
        favorites.contains { $0.matches(id: game.id) }
    }

    func toggleFavorite(_ game: Game) {
        if let index = favorites.firstIndex(where: { $0.matches(id: game.id) }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(game, at: 0)
        }
        save(favorites, Key.favorites)
    }

    func clearFavorites() {
        favorites.removeAll()
        save(favorites, Key.favorites)
    }

    // MARK: - Recents

    func noteLaunch(_ game: Game) {
        recents.removeAll { $0.matches(id: game.id) }
        recents.insert(game, at: 0)
        if recents.count > Self.recentsLimit {
            recents.removeLast(recents.count - Self.recentsLimit)
        }
        save(recents, Key.recents)
    }

    func clearRecents() {
        recents.removeAll()
        save(recents, Key.recents)
    }

    // MARK: - Up next

    func isQueued(_ game: Game) -> Bool {
        queue.contains { $0.matches(id: game.id) }
    }

    func toggleQueue(_ game: Game) {
        if isQueued(game) {
            queue.removeAll { $0.matches(id: game.id) }
        } else {
            queue.append(game)
        }
        save(queue, Key.queue)
    }

    func removeFromQueue(_ game: Game) {
        queue.removeAll { $0.matches(id: game.id) }
        save(queue, Key.queue)
    }

    @discardableResult
    func takeNextFromQueue() -> Game? {
        guard !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        save(queue, Key.queue)
        return next
    }

    // MARK: - Lists

    func createList(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lists.append(GameList(name: clean))
        save(lists, Key.lists)
    }

    func deleteList(_ list: GameList) {
        lists.removeAll { $0.id == list.id }
        save(lists, Key.lists)
    }

    func renameList(_ list: GameList, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[index].name = clean
        save(lists, Key.lists)
    }

    func list(withID id: UUID) -> GameList? {
        lists.first { $0.id == id }
    }

    func toggle(game: Game, inListWithID id: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        if let existing = lists[index].gameIDs.firstIndex(where: {
            $0.caseInsensitiveCompare(game.id) == .orderedSame
        }) {
            lists[index].gameIDs.remove(at: existing)
        } else {
            lists[index].gameIDs.append(game.id)
        }
        save(lists, Key.lists)
    }

    func contains(game: Game, inListWithID id: UUID) -> Bool {
        list(withID: id)?.gameIDs.contains { $0.caseInsensitiveCompare(game.id) == .orderedSame } ?? false
    }

    /// Resolves a list's IDs against the catalog, falling back to whatever the
    /// library already knows, so lists survive a catalog outage too.
    func games(in list: GameList, catalog: Catalog) -> [Game] {
        list.gameIDs.compactMap { id in
            catalog.game(id: id)
                ?? favorites.first { $0.matches(id: id) }
                ?? recents.first { $0.matches(id: id) }
        }
    }

    // MARK: - Activity

    func record(_ record: PlayRecord) {
        activity.insert(record, at: 0)
        if activity.count > Self.activityLimit {
            activity.removeLast(activity.count - Self.activityLimit)
        }
        save(activity, Key.activity)
    }

    func clearActivity() {
        activity.removeAll()
        save(activity, Key.activity)
    }

    var totalPlaytime: TimeInterval {
        activity.reduce(0) { $0 + $1.seconds }
    }

    func playtime(forGameID id: String) -> TimeInterval {
        activity.filter { $0.gameID.caseInsensitiveCompare(id) == .orderedSame }
            .reduce(0) { $0 + $1.seconds }
    }

    // MARK: - Storage

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
