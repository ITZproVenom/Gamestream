import Foundation
import SwiftUI

struct CatalogGame: Identifiable, Hashable {
    var id: String
    var slug: String
    var title: String
    var tagline: String
    var genre: String
    var provider: String
    var featured: Bool
    var accent: UInt32

    var tracked: TrackedGame {
        TrackedGame(id: id, slug: slug, title: title, lastSeen: Date(), isFavorite: false)
    }
}

enum GameCatalog {
    static let genreNames = ["Racing", "Shooter", "Action", "Adventure", "Sandbox", "RPG", "Survival", "Platformer"]

    static let games: [CatalogGame] = [
        CatalogGame(id: "9PNJ1RJL8SL9", slug: "forza-horizon-5", title: "Forza Horizon 5",
                    tagline: "Open-world racing across Mexico", genre: "Racing", provider: "Xbox Cloud", featured: true, accent: 0xE85D04),
        CatalogGame(id: "9NP1P1W3J5C6", slug: "halo-infinite", title: "Halo Infinite",
                    tagline: "Master Chief returns to the ring", genre: "Shooter", provider: "Xbox Cloud", featured: true, accent: 0x2D6A4F),
        CatalogGame(id: "9N87K6P39X81", slug: "fortnite", title: "Fortnite",
                    tagline: "Battle Royale, Zero Build, and more", genre: "Action", provider: "Xbox Cloud", featured: true, accent: 0x5A189A),
        CatalogGame(id: "9NBLGGH2JHXJ", slug: "minecraft", title: "Minecraft",
                    tagline: "Build, explore, survive", genre: "Sandbox", provider: "Xbox Cloud", featured: true, accent: 0x40916C),
        CatalogGame(id: "9NN3HCKW5TPC", slug: "sea-of-thieves", title: "Sea of Thieves",
                    tagline: "Sail, plunder, and tell tall tales", genre: "Adventure", provider: "Xbox Cloud", featured: true, accent: 0x0077B6),
        CatalogGame(id: "9NBLGGH32QM8", slug: "roblox", title: "Roblox",
                    tagline: "Millions of player-created worlds", genre: "Sandbox", provider: "Xbox Cloud", featured: false, accent: 0xE63946),
        CatalogGame(id: "9NBLGGH4R315", slug: "call-of-duty", title: "Call of Duty",
                    tagline: "Multiplayer and Warzone on the cloud", genre: "Shooter", provider: "Xbox Cloud", featured: false, accent: 0x6C757D),
        CatalogGame(id: "9MT8ND8BP6J2", slug: "starfield", title: "Starfield",
                    tagline: "Bethesda's jump into the stars", genre: "RPG", provider: "Xbox Cloud", featured: false, accent: 0x3D405B),
        CatalogGame(id: "9NBLGGH42THS", slug: "grounded", title: "Grounded",
                    tagline: "Survive the backyard, ant-sized", genre: "Survival", provider: "Xbox Cloud", featured: false, accent: 0x588157),
        CatalogGame(id: "9N9J38LPVSM3", slug: "palworld", title: "Palworld",
                    tagline: "Catch pals, build bases, survive", genre: "Survival", provider: "Xbox Cloud", featured: false, accent: 0x00B4D8),
        CatalogGame(id: "9NBLGGH43KHL", slug: "psychonauts-2", title: "Psychonauts 2",
                    tagline: "A trip through wild minds", genre: "Adventure", provider: "Xbox Cloud", featured: false, accent: 0x9B5DE5),
        CatalogGame(id: "9PMQDM08SNK9", slug: "hi-fi-rush", title: "Hi-Fi Rush",
                    tagline: "Rhythm-action in a music studio", genre: "Action", provider: "Xbox Cloud", featured: false, accent: 0xF72585),
        CatalogGame(id: "9N1CD16C2NQ0", slug: "pentiment", title: "Pentiment",
                    tagline: "A medieval mystery in ink", genre: "Adventure", provider: "Xbox Cloud", featured: false, accent: 0xBC6C25),
        CatalogGame(id: "9N2S0C936B3P", slug: "ori-and-the-will-of-the-wisps", title: "Ori and the Will of the Wisps",
                    tagline: "A beautiful Metroidvania journey", genre: "Platformer", provider: "Xbox Cloud", featured: false, accent: 0x4CC9F0),
        CatalogGame(id: "9NBLGGH1Z6FQ", slug: "cuphead", title: "Cuphead",
                    tagline: "Run-and-gun with jazz-age style", genre: "Action", provider: "Xbox Cloud", featured: false, accent: 0xD00000)
    ]

    static var featured: [CatalogGame] { games.filter(\.featured) }

    static func game(id: String) -> CatalogGame? {
        games.first(where: { $0.id == id })
    }

    static func catalog(from tracked: TrackedGame) -> CatalogGame {
        game(id: tracked.id) ?? CatalogGame(
            id: tracked.id,
            slug: tracked.slug,
            title: tracked.title,
            tagline: "Xbox Cloud Gaming",
            genre: "Cloud",
            provider: "Xbox Cloud",
            featured: false,
            accent: 0x4361EE
        )
    }

    static func matches(_ query: String) -> [CatalogGame] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return games }
        return games.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.genre.localizedCaseInsensitiveContains(q) ||
            $0.tagline.localizedCaseInsensitiveContains(q) ||
            $0.slug.localizedCaseInsensitiveContains(q.replacingOccurrences(of: " ", with: "-"))
        }
    }

    static func related(to game: CatalogGame, limit: Int = 6) -> [CatalogGame] {
        let sameGenre = games.filter { $0.genre == game.genre && $0.id != game.id }
        if sameGenre.count >= 2 { return Array(sameGenre.prefix(limit)) }
        return Array(games.filter { $0.id != game.id }.prefix(limit))
    }

    static func shelves(favorites: [TrackedGame], recents: [TrackedGame]) -> [(String, [CatalogGame])] {
        var rows: [(String, [CatalogGame])] = []
        if !recents.isEmpty {
            rows.append(("Continue playing", recents.map { catalog(from: $0) }))
        }
        if !favorites.isEmpty {
            rows.append(("Favorites", favorites.map { catalog(from: $0) }))
        }
        rows.append(("Popular on Cloud", Array(games.prefix(8))))
        for genre in genreNames {
            let items = games.filter { $0.genre == genre }
            if items.count >= 2 {
                rows.append((genre, items))
            }
        }
        return rows
    }
}

@MainActor
final class ArtworkStore: ObservableObject {
    static let shared = ArtworkStore()
    @Published private(set) var urls: [String: URL] = [:]
    private var inflight: Set<String> = []

    func url(for productId: String) -> URL? { urls[productId] }

    func prefetch(_ ids: [String]) {
        ids.forEach { load($0) }
    }

    func load(_ productId: String) {
        guard urls[productId] == nil, !inflight.contains(productId), !productId.isEmpty else { return }
        inflight.insert(productId)
        guard let endpoint = URL(string: "https://displaycatalog.mp.microsoft.com/v7.0/products/\(productId)?market=US&languages=en-US") else {
            inflight.remove(productId)
            return
        }
        Task {
            defer { inflight.remove(productId) }
            do {
                let (data, _) = try await URLSession.shared.data(from: endpoint)
                if let url = Self.parsePoster(from: data) {
                    urls[productId] = url
                }
            } catch {
            }
        }
    }

    private static func parsePoster(from data: Data) -> URL? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let products = json["Products"] as? [[String: Any]],
            let first = products.first,
            let localized = first["LocalizedProperties"] as? [[String: Any]],
            let props = localized.first,
            let images = props["Images"] as? [[String: Any]]
        else { return nil }

        let preferred = ["Poster", "BoxArt", "BrandedKeyArt", "TitledHeroArt", "SuperHeroArt", "Screenshot"]
        for purpose in preferred {
            if let match = images.first(where: { ($0["ImagePurpose"] as? String) == purpose }),
               let raw = match["Uri"] as? String,
               let url = normalizedImageURL(raw) {
                return url
            }
        }
        if let raw = images.first?["Uri"] as? String {
            return normalizedImageURL(raw)
        }
        return nil
    }

    private static func normalizedImageURL(_ raw: String) -> URL? {
        if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
        return URL(string: raw)
    }
}
