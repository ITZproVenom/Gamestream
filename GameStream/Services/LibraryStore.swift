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

    /// Lookup tables, so a tile asking "is this a favourite?" or "how long
    /// has this been played?" does not walk a list.
    ///
    /// The library grid asks those questions for every visible tile on every
    /// redraw, and the answers used to come from a scan: favourites were
    /// compared one by one, and the playtime of a game was summed by
    /// comparing every session in the activity log - which is then sorted
    /// with, so the whole log was walked thousands of times for one frame.
    private var favoriteIndex: Set<String> = []
    private var queuedIndex: Set<String> = []
    private var playtimeIndex: [String: TimeInterval] = [:]
    /// The sessions behind each game, for an estimate of how long a queued
    /// game is likely to take.
    private var sessionsByGame: [String: [TimeInterval]] = [:]

    private enum Key {
        static let favorites = "library.favorites.v1"
        static let recents = "library.recents.v1"
        static let queue = "library.queue.v1"
        static let lists = "library.lists.v1"
        static let activity = "library.activity.v1"
        static let known = "library.known.v1"
    }

    private static let recentsLimit = 30
    private static let activityLimit = 300
    private static let knownLimit = 600

    private init() {
        favorites = Self.load([Game].self, Key.favorites) ?? []
        recents = Self.load([Game].self, Key.recents) ?? []
        queue = Self.load([Game].self, Key.queue) ?? []
        lists = Self.load([GameList].self, Key.lists) ?? []
        activity = Self.load([PlayRecord].self, Key.activity) ?? []
        known = Self.load([String: Game].self, Key.known) ?? [:]
        rebuildIndexes()
    }

    /// Rebuilds the lookup tables. Cheap enough to do whenever one of the
    /// lists changes, and it turns every per-tile question into a dictionary
    /// lookup.
    private func rebuildIndexes() {
        favoriteIndex = Set(favorites.map { $0.id.lowercased() })
        queuedIndex = Set(queue.map { $0.id.lowercased() })
        var totals: [String: TimeInterval] = [:]
        var sessions: [String: [TimeInterval]] = [:]
        for record in activity {
            let key = record.gameID.lowercased()
            totals[key, default: 0] += record.seconds
            sessions[key, default: []].append(record.seconds)
        }
        playtimeIndex = totals
        sessionsByGame = sessions
    }

    /// Every game the library has ever held, kept so a list can still show a
    /// game the catalog has stopped returning.
    ///
    /// Favourites and recents store the whole `Game`, which is why they
    /// survive a thin catalog response. A list stores identifiers only, so it
    /// had the original 1.x problem all to itself: a game that left Game Pass,
    /// or a catalog request that simply did not include it, dropped out of the
    /// list with no trace and no explanation.
    private var known: [String: Game] = [:]

    private func remember(_ game: Game) {
        let key = game.id.lowercased()
        guard known[key] != game else { return }
        known[key] = game
        // Bounded, so a long-lived install cannot grow this without limit.
        if known.count > Self.knownLimit {
            let keep = Set(
                (favorites + recents + queue).map { $0.id.lowercased() }
                    + lists.flatMap { $0.gameIDs }.map { $0.lowercased() }
            )
            known = known.filter { keep.contains($0.key) }
        }
        save(known, Key.known)
    }

    func knownGame(id: String) -> Game? { known[id.lowercased()] }

    // MARK: - Favourites

    func isFavorite(_ game: Game) -> Bool {
        favoriteIndex.contains(game.id.lowercased())
    }

    func toggleFavorite(_ game: Game) {
        if let index = favorites.firstIndex(where: { $0.matches(id: game.id) }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(game, at: 0)
        }
        remember(game)
        save(favorites, Key.favorites)
        rebuildIndexes()
    }

    func clearFavorites() {
        favorites.removeAll()
        save(favorites, Key.favorites)
        rebuildIndexes()
    }

    // MARK: - Recents

    func noteLaunch(_ game: Game) {
        recents.removeAll { $0.matches(id: game.id) }
        recents.insert(game, at: 0)
        remember(game)
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
        queuedIndex.contains(game.id.lowercased())
    }

    func toggleQueue(_ game: Game) {
        if isQueued(game) {
            queue.removeAll { $0.matches(id: game.id) }
        } else {
            queue.append(game)
        }
        remember(game)
        save(queue, Key.queue)
        rebuildIndexes()
    }

    func removeFromQueue(_ game: Game) {
        queue.removeAll { $0.matches(id: game.id) }
        save(queue, Key.queue)
        rebuildIndexes()
    }

    @discardableResult
    func takeNextFromQueue() -> Game? {
        guard !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        save(queue, Key.queue)
        return next
    }

    // MARK: - Lists

    @discardableResult
    func createList(named name: String, including game: Game? = nil) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let list = GameList(name: clean, gameIDs: game.map { [$0.id] } ?? [])
        lists.append(list)
        if let game { remember(game) }
        save(lists, Key.lists)
        return list.id
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
            remember(game)
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
                ?? queue.first { $0.matches(id: id) }
                ?? knownGame(id: id)
        }
    }

    // MARK: - Activity

    func record(_ record: PlayRecord) {
        activity.insert(record, at: 0)
        if activity.count > Self.activityLimit {
            activity.removeLast(activity.count - Self.activityLimit)
        }
        save(activity, Key.activity)
        rebuildIndexes()
    }

    /// Removes a single session. Clearing everything was the only way to
    /// get rid of one mistaken entry.
    func deleteActivity(_ record: PlayRecord) {
        activity.removeAll { $0.id == record.id }
        save(activity, Key.activity)
        rebuildIndexes()
    }

    func clearActivity() {
        activity.removeAll()
        save(activity, Key.activity)
        rebuildIndexes()
    }

    var totalPlaytime: TimeInterval {
        activity.reduce(0) { $0 + $1.seconds }
    }

    func playtime(forGameID id: String) -> TimeInterval {
        playtimeIndex[id.lowercased()] ?? 0
    }

    /// How long a session usually lasts for this player.
    ///
    /// With no history there is nothing to go on, so Microsoft's own cloud
    /// session length is used: a queue of games would otherwise be reported
    /// as taking no time at all.
    var averageSessionLength: TimeInterval {
        guard !activity.isEmpty else { return 30 * 60 }
        let total = activity.reduce(0) { $0 + $1.seconds }
        return total / Double(activity.count)
    }

    /// How long one game is likely to take, from this player's own sessions
    /// with it, and otherwise from how long they usually play.
    func estimatedSessionLength(for game: Game) -> TimeInterval {
        let sessions = sessionsByGame[game.id.lowercased()] ?? []
        guard !sessions.isEmpty else { return averageSessionLength }
        return sessions.reduce(0, +) / Double(sessions.count)
    }

    /// How long the queued games are likely to take in total.
    var queueEstimatedLength: TimeInterval {
        queue.reduce(0) { $0 + estimatedSessionLength(for: $1) }
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
