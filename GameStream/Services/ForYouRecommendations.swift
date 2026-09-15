import Foundation

extension GameCatalog {
    static func forYou(favorites: [TrackedGame], recents: [TrackedGame], limit: Int = 10) -> [CatalogGame] {
        let seen = Set(recents.map(\.id) + favorites.map(\.id))
        var genreWeight: [String: Int] = [:]
        for game in recents.prefix(6).map({ catalog(from: $0) }) {
            genreWeight[game.genre, default: 0] += 3
        }
        for game in favorites.prefix(8).map({ catalog(from: $0) }) {
            genreWeight[game.genre, default: 0] += 2
        }
        if genreWeight.isEmpty {
            return Array(featured.prefix(limit))
        }
        return games
            .filter { !seen.contains($0.id) }
            .map { game -> (CatalogGame, Int) in
                var score = genreWeight[game.genre, default: 0]
                if game.featured { score += 1 }
                return (game, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.title < rhs.0.title
            }
            .prefix(limit)
            .map(\.0)
    }

    static func becauseYouPlayed(recents: [TrackedGame], limitPerShelf: Int = 6) -> [(String, [CatalogGame])] {
        var rows: [(String, [CatalogGame])] = []
        var used = Set(recents.map(\.id))
        for recent in recents.prefix(3) {
            let seed = catalog(from: recent)
            let picks = related(to: seed, limit: limitPerShelf + 4)
                .filter { !used.contains($0.id) }
                .prefix(limitPerShelf)
            let list = Array(picks)
            guard list.count >= 2 else { continue }
            list.forEach { used.insert($0.id) }
            rows.append(("Because you played \(seed.title)", list))
        }
        return rows
    }

    static func relativePlayLabel(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 90 { return "Just now" }
        if seconds < 3600 {
            let mins = max(1, Int(seconds / 60))
            return "\(mins) min ago"
        }
        if seconds < 86_400 {
            let hours = max(1, Int(seconds / 3600))
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        let days = max(1, Int(seconds / 86_400))
        if days == 1 { return "Yesterday" }
        if days < 14 { return "\(days) days ago" }
        return "Recently played"
    }

    static func hubShelves(favorites: [TrackedGame], recents: [TrackedGame]) -> [(String, [CatalogGame])] {
        var rows: [(String, [CatalogGame])] = []
        if !recents.isEmpty {
            rows.append(("Continue playing", recents.map { catalog(from: $0) }))
        }
        if !favorites.isEmpty {
            rows.append(("Favorites", favorites.map { catalog(from: $0) }))
        }
        let picks = forYou(favorites: favorites, recents: recents)
        if !picks.isEmpty {
            rows.append(("For You", picks))
        }
        rows.append(contentsOf: becauseYouPlayed(recents: recents))
        rows.append(("Popular on Cloud", Array(games.prefix(8))))
        rows.append(contentsOf: discoveryShelves())
        for genre in genreNames {
            let items = games.filter { $0.genre == genre }
            if items.count >= 2 {
                rows.append((genre, items))
            }
        }
        return rows
    }
}
