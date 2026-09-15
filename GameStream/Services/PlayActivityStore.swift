import Foundation
import Combine

struct PlayStat: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var slug: String
    var totalSeconds: TimeInterval
    var sessionCount: Int
    var lastPlayed: Date
    var weekSeconds: TimeInterval
    var weekAnchor: Date
}

@MainActor
final class PlayActivityStore: ObservableObject {
    static let shared = PlayActivityStore()

    @Published private(set) var stats: [PlayStat] = []
    @Published private(set) var liveSeconds: TimeInterval = 0
    @Published private(set) var activeTitle: String?

    private let key = "GameStream.playActivity.v1"
    private var activeId: String?
    private var activeStart: Date?
    private var tick: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            stats = (try? JSONDecoder().decode([PlayStat].self, from: data)) ?? []
        }
        normalizeWeeks()
    }

    func begin(id: String, title: String, slug: String) {
        if activeId == id {
            activeTitle = title
            ensureStat(id: id, title: title, slug: slug)
            return
        }
        endActiveIfNeeded()
        guard !id.isEmpty else { return }
        activeId = id
        activeTitle = title
        activeStart = Date()
        liveSeconds = 0
        ensureStat(id: id, title: title, slug: slug)
        startTick()
    }

    func end() {
        endActiveIfNeeded()
        stopTick()
        liveSeconds = 0
        activeTitle = nil
    }

    func stat(for id: String) -> PlayStat? {
        stats.first(where: { $0.id == id })
    }

    var weekTotal: TimeInterval {
        stats.reduce(0) { $0 + $1.weekSeconds } + liveSeconds
    }

    var allTimeTotal: TimeInterval {
        stats.reduce(0) { $0 + $1.totalSeconds } + liveSeconds
    }

    var rankedThisWeek: [PlayStat] {
        stats
            .map { stat in
                var copy = stat
                if stat.id == activeId { copy.weekSeconds += liveSeconds }
                return copy
            }
            .filter { $0.weekSeconds > 0 || $0.id == activeId }
            .sorted { $0.weekSeconds > $1.weekSeconds }
    }

    var mostPlayedThisWeek: PlayStat? { rankedThisWeek.first }

    func gamesForHub() -> [CatalogGame] {
        rankedThisWeek.map { GameCatalog.catalog(from: TrackedGame(id: $0.id, slug: $0.slug, title: $0.title, lastSeen: $0.lastPlayed, isFavorite: false)) }
    }

    func clear() {
        end()
        stats = []
        persist()
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total % 60)s"
    }

    private func startTick() {
        stopTick()
        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.activeStart else { return }
                self.liveSeconds = Date().timeIntervalSince(start)
            }
        }
        if let tick { RunLoop.main.add(tick, forMode: .common) }
    }

    private func stopTick() {
        tick?.invalidate()
        tick = nil
    }

    private func endActiveIfNeeded() {
        guard let id = activeId, let start = activeStart else {
            activeId = nil
            activeStart = nil
            return
        }
        let elapsed = max(0, Date().timeIntervalSince(start))
        if elapsed >= 20 {
            record(id: id, seconds: elapsed)
        }
        activeId = nil
        activeStart = nil
    }

    private func record(id: String, seconds: TimeInterval) {
        normalizeWeeks()
        guard let index = stats.firstIndex(where: { $0.id == id }) else { return }
        stats[index].totalSeconds += seconds
        stats[index].weekSeconds += seconds
        stats[index].sessionCount += 1
        stats[index].lastPlayed = Date()
        persist()
    }

    private func ensureStat(id: String, title: String, slug: String) {
        if let index = stats.firstIndex(where: { $0.id == id }) {
            if title.count >= stats[index].title.count { stats[index].title = title }
            if !slug.isEmpty { stats[index].slug = slug }
            return
        }
        stats.insert(
            PlayStat(id: id, title: title, slug: slug, totalSeconds: 0, sessionCount: 0, lastPlayed: Date(), weekSeconds: 0, weekAnchor: Self.startOfWeek()),
            at: 0
        )
        persist()
    }

    private func normalizeWeeks() {
        let anchor = Self.startOfWeek()
        var changed = false
        for i in stats.indices where stats[i].weekAnchor < anchor {
            stats[i].weekSeconds = 0
            stats[i].weekAnchor = anchor
            changed = true
        }
        if changed { persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func startOfWeek() -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }
}
