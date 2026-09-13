import Foundation
import Combine

@MainActor
final class PlayQueueStore: ObservableObject {
    static let shared = PlayQueueStore()
    @Published private(set) var games: [TrackedGame] = []
    private let key = "GameStream.playQueue.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            games = (try? JSONDecoder().decode([TrackedGame].self, from: data)) ?? []
        }
    }

    func isQueued(_ id: String) -> Bool {
        games.contains(where: { $0.id == id })
    }

    func enqueue(_ game: TrackedGame) {
        if isQueued(game.id) { return }
        var item = game
        item.lastSeen = Date()
        games.append(item)
        if games.count > 16 { games = Array(games.prefix(16)) }
        persist()
    }

    func dequeue(_ game: TrackedGame) {
        games.removeAll { $0.id == game.id }
        persist()
    }

    func toggle(_ game: TrackedGame) {
        if isQueued(game.id) { dequeue(game) } else { enqueue(game) }
    }

    func clear() {
        games = []
        persist()
    }

    @discardableResult
    func popFront() -> TrackedGame? {
        guard !games.isEmpty else { return nil }
        let next = games.removeFirst()
        persist()
        return next
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension SessionStore {
    var playQueue: [TrackedGame] { PlayQueueStore.shared.games }
    var nextQueuedGame: TrackedGame? { PlayQueueStore.shared.games.first }
    func isQueued(_ id: String) -> Bool { PlayQueueStore.shared.isQueued(id) }
    func enqueue(_ game: TrackedGame) { PlayQueueStore.shared.enqueue(game); objectWillChange.send() }
    func dequeue(_ game: TrackedGame) { PlayQueueStore.shared.dequeue(game); objectWillChange.send() }
    func toggleQueue(_ game: TrackedGame) { PlayQueueStore.shared.toggle(game); objectWillChange.send() }
    func clearQueue() { PlayQueueStore.shared.clear(); objectWillChange.send() }

    @discardableResult
    func playNextQueued() -> Bool {
        guard let next = PlayQueueStore.shared.popFront() else { return false }
        objectWillChange.send()
        playGame(next)
        return true
    }
}
