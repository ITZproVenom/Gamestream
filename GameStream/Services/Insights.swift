import Foundation

/// Playtime totals derived from the activity log.
///
/// These are computed rather than stored: the activity log is the single
/// source of truth, so a statistic can never disagree with the sessions it
/// was built from.
struct DayTotal: Identifiable, Hashable, Sendable {
    let day: Date
    let seconds: TimeInterval

    var id: Date { day }

    var weekdayInitial: String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let index = Calendar.current.component(.weekday, from: day) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

struct GameTotal: Identifiable, Hashable, Sendable {
    let gameID: String
    let title: String
    let seconds: TimeInterval
    let sessions: Int

    var id: String { gameID }
}

extension LibraryStore {
    /// Totals for the last `days` days, oldest first, including empty days so
    /// a chart keeps an honest shape.
    func dailyTotals(days: Int = 7) -> [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var buckets: [Date: TimeInterval] = [:]
        for record in activity {
            let day = calendar.startOfDay(for: record.startedAt)
            guard let distance = calendar.dateComponents([.day], from: day, to: today).day,
                  distance >= 0, distance < days else { continue }
            buckets[day, default: 0] += record.seconds
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayTotal(day: day, seconds: buckets[day] ?? 0)
        }
    }

    func topGames(limit: Int = 5) -> [GameTotal] {
        var totals: [String: GameTotal] = [:]
        for record in activity {
            let key = record.gameID.uppercased()
            if let existing = totals[key] {
                totals[key] = GameTotal(gameID: existing.gameID, title: existing.title,
                                        seconds: existing.seconds + record.seconds,
                                        sessions: existing.sessions + 1)
            } else {
                totals[key] = GameTotal(gameID: record.gameID, title: record.title,
                                        seconds: record.seconds, sessions: 1)
            }
        }
        return totals.values.sorted { $0.seconds > $1.seconds }.prefix(limit).map { $0 }
    }

    var playtimeThisWeek: TimeInterval {
        dailyTotals(days: 7).reduce(0) { $0 + $1.seconds }
    }

    var playtimeToday: TimeInterval {
        let today = Calendar.current.startOfDay(for: Date())
        return activity
            .filter { $0.startedAt >= today }
            .reduce(0) { $0 + $1.seconds }
    }

    var longestSession: PlayRecord? {
        activity.max { $0.seconds < $1.seconds }
    }

    /// Consecutive days with at least one session, counting back from today.
    /// A day with no play ends the streak; today not having play yet does not.
    var streakDays: Int {
        let calendar = Calendar.current
        let played = Set(activity.map { calendar.startOfDay(for: $0.startedAt) })
        guard !played.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: Date())
        if !played.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  played.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while played.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    func sessions(forGameID id: String) -> Int {
        activity.filter { $0.gameID.caseInsensitiveCompare(id) == .orderedSame }.count
    }

    /// The game to offer as "resume": whatever was played last.
    var resumeCandidate: Game? { recents.first }
}

extension Catalog {
    /// The shelf at the top of Home. Only titles with hero artwork qualify,
    /// because a hero card with a stretched poster looks broken.
    var featured: [Game] {
        let withHero = games.filter { $0.heroURL != nil }
        return Array((withHero.isEmpty ? games : withHero).prefix(8))
    }

    func randomGame(excluding excluded: Set<String> = []) -> Game? {
        games.filter { !excluded.contains($0.id.uppercased()) }.randomElement()
    }
}

/// Recent search terms, kept small and local.
@MainActor
final class SearchHistory: ObservableObject {
    static let shared = SearchHistory()

    @Published private(set) var terms: [String] = []

    private let key = "search.recents.v1"
    private let limit = 8

    private init() {
        terms = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func record(_ term: String) {
        let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return }
        terms.removeAll { $0.caseInsensitiveCompare(clean) == .orderedSame }
        terms.insert(clean, at: 0)
        if terms.count > limit { terms.removeLast(terms.count - limit) }
        UserDefaults.standard.set(terms, forKey: key)
    }

    func clear() {
        terms.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
    }
}
