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
    var posterURL: URL?

    var tracked: TrackedGame {
        TrackedGame(id: id, slug: slug, title: title, lastSeen: Date(), isFavorite: false)
    }
}

extension Notification.Name {
    static let catalogDidChange = Notification.Name("GameStreamCatalogDidChange")
}

@MainActor
final class CatalogLiveStore: ObservableObject {
    static let shared = CatalogLiveStore()
    @Published private(set) var revision: Int = 0
    func bump() { revision += 1 }
}

enum GameCatalog {
    private static let seed: [CatalogGame] = [
        item("9NNX1VVR3KNQ", "forza-horizon-5", "Forza Horizon 5",
             "Open-world racing across Mexico", "Racing", true, 0xE85D04,
             "https://store-images.s-microsoft.com/image/apps.56329.13734397844529069.202e3fc9-37d6-4853-a58b-fabe504b71e8.b2447b97-7903-48de-8a49-9669d0495c4f"),
        item("9NP1P1WFS0LB", "halo-infinite", "Halo Infinite",
             "Master Chief returns to the ring", "Shooter", true, 0x2D6A4F,
             "https://store-images.s-microsoft.com/image/apps.21536.13727851868390641.c9cc5f66-aff8-406c-af6b-440838730be0.68796bde-cbf5-4eaa-a299-011417041da6"),
        item("BT5P2X999VH2", "fortnite", "Fortnite",
             "Battle Royale, Zero Build, and more", "Action", true, 0x5A189A,
             "https://store-images.s-microsoft.com/image/apps.19309.70702278257994163.7867c110-12f5-414d-88b4-e851aea24391.e7460671-6dd2-47d7-af59-71118b6d060c"),
        item("9NXP44L49SHJ", "minecraft", "Minecraft",
             "Build, explore, survive", "Sandbox", true, 0x40916C,
             "https://store-images.s-microsoft.com/image/apps.808.14492077886571533.be42f4bd-887b-4430-8ed0-622341b4d2b0.c8274c53-105e-478b-9f4b-41b8088210a3"),
        item("9P2N57MC619K", "sea-of-thieves", "Sea of Thieves",
             "Sail, plunder, and tell tall tales", "Adventure", true, 0x0077B6,
             "https://store-images.s-microsoft.com/image/apps.29206.14554784103656548.069efce3-9249-4074-a169-183b727043f8.03688f8c-edc0-416b-bebb-9d98a01c25f5"),
        item("BQ1TN1T79V9K", "roblox", "Roblox",
             "Millions of player-created worlds", "Sandbox", false, 0xE63946,
             "https://store-images.s-microsoft.com/image/apps.3683.68327322396008232.ddd32983-30da-4856-a0ef-70bb8840e88d.cb3ff148-2c1f-4b84-9eea-ff80eda50c2d"),
        item("9N201KQXS5BM", "call-of-duty", "Call of Duty",
             "Multiplayer and Warzone on the cloud", "Shooter", false, 0x6C757D,
             "https://store-images.s-microsoft.com/image/apps.30472.13966330883349940.9a0bbc3f-3231-4a17-ab16-55eb671f1755.d9aecc85-6637-4e56-a359-009944a02940"),
        item("9NCJSXWZTP88", "starfield", "Starfield",
             "Bethesda's jump into the stars", "RPG", false, 0x3D405B,
             "https://store-images.s-microsoft.com/image/apps.35187.13567343664224659.1eb6fdf9-8a0b-4344-a135-ab17dfa3c609.c83b6d6a-56c3-4c3f-8b31-456cfb21c3b7"),
        item("9PJTHRNVH62H", "grounded", "Grounded",
             "Survive the backyard, ant-sized", "Survival", false, 0x588157,
             "https://store-images.s-microsoft.com/image/apps.20293.14280109286674604.0f240f37-6e7f-43b4-bd81-aabc884bc103.16d2c3ac-d4fa-4540-8f7d-4c716d393513"),
        item("9NKV34XDW014", "palworld", "Palworld",
             "Catch pals, build bases, survive", "Survival", false, 0x00B4D8,
             "https://store-images.s-microsoft.com/image/apps.49778.13654268679289325.ececb946-5639-4e77-b347-9d188d4e7e02.9102215b-349a-4f6d-b9a3-2c14908481f1"),
        item("9NBR2VXT87SJ", "psychonauts-2", "Psychonauts 2",
             "A trip through wild minds", "Adventure", false, 0x9B5DE5,
             "https://store-images.s-microsoft.com/image/apps.59150.13578175979543723.424401c3-5602-4e35-abfc-c00f9156296a.99cd91cb-4b52-4353-b333-28a9e48f06fe"),
        item("9NFTC552K3GJ", "hi-fi-rush", "Hi-Fi Rush",
             "Rhythm-action in a music studio", "Action", false, 0xF72585,
             "https://store-images.s-microsoft.com/image/apps.54250.13592675470908447.79efa8be-9602-4911-867c-3b27d26ad414.5083e064-e3e9-4a23-bb10-684f7be75d15"),
        item("9NX6K9HN4F4K", "pentiment", "Pentiment",
             "A medieval mystery in ink", "Adventure", false, 0xBC6C25,
             "https://store-images.s-microsoft.com/image/apps.32118.14431229486160986.b3655366-4704-41dd-bb1b-0ea3f2425df6.808122ac-ca66-4ac7-8efc-134da0e929ca"),
        item("9N8CD0XZKLP4", "ori-and-the-will-of-the-wisps", "Ori and the Will of the Wisps",
             "A beautiful Metroidvania journey", "Platformer", false, 0x4CC9F0,
             "https://store-images.s-microsoft.com/image/apps.18799.14047496556148589.9fda5cef-7995-4dbb-a626-66d2ab3feb4f.1e167626-8b7d-47b4-9fe5-d06a43ac6677"),
        item("9NB0115C9WNM", "cuphead", "Cuphead",
             "Run-and-gun with jazz-age style", "Action", false, 0xD00000,
             "https://store-images.s-microsoft.com/image/apps.36678.13527301958862136.ffa8c20b-226b-443c-8d6c-cce51dca9945.7170663c-a4e2-46db-a81b-aa22c30d6d44")
    ]

    static func game(id: String) -> CatalogGame? {
        games.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame })
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
            accent: 0x4361EE,
            posterURL: nil
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

    private static func item(
        _ id: String, _ slug: String, _ title: String, _ tagline: String,
        _ genre: String, _ featured: Bool, _ accent: UInt32, _ poster: String
    ) -> CatalogGame {
        CatalogGame(
            id: id, slug: slug, title: title, tagline: tagline, genre: genre,
            provider: "Xbox Cloud", featured: featured, accent: accent,
            posterURL: URL(string: poster)
        )
    }

    private static var live: [CatalogGame] = seed
    private static var _cachedGenreNames: [String]?
    private static var _cachedBrowse: [CatalogGame]?

    static var games: [CatalogGame] { live }

    static var sortedBrowse: [CatalogGame] {
        if let cached = _cachedBrowse { return cached }
        let result = live.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        _cachedBrowse = result
        return result
    }

    static var genreNames: [String] {
        if let cached = _cachedGenreNames { return cached }
        let known = ["Racing", "Shooter", "Action", "Adventure", "Sandbox", "RPG", "Survival", "Platformer", "Sports", "Strategy", "Simulation", "Fighting", "Puzzle"]
        let present = Set(live.map(\.genre))
        let result = known.filter { present.contains($0) } + present.subtracting(known).sorted()
        _cachedGenreNames = result
        return result
    }

    static var featured: [CatalogGame] { games.filter(\.featured) }

    @MainActor
    static func installLiveCatalog(_ incoming: [CatalogGame]) {
        var seen = Set<String>()
        var unique: [CatalogGame] = []
        unique.reserveCapacity(incoming.count)
        for game in incoming {
            let key = game.id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            unique.append(game)
        }
        guard unique.count >= 20 else { return }
        live = unique.enumerated().map { index, game in
            var copy = game
            copy.featured = index < 8 || seed.contains(where: { $0.id.caseInsensitiveCompare(game.id) == .orderedSame && $0.featured })
            return copy
        }
        _cachedGenreNames = nil
        _cachedBrowse = nil
        ArtworkStore.shared.ingest(live)
        CatalogLiveStore.shared.bump()
        NotificationCenter.default.post(name: .catalogDidChange, object: nil)
    }
}

@MainActor
final class ArtworkStore: ObservableObject {
    static let shared = ArtworkStore()
    @Published private(set) var urls: [String: URL] = [:]
    private var inflight: Set<String> = []
    private var fetchGeneration = 0

    init() {
        ingest(GameCatalog.games)
    }

    func ingest(_ games: [CatalogGame]) {
        for game in games {
            if let poster = game.posterURL {
                urls[game.id] = poster
            }
        }
    }

    func url(for productId: String) -> URL? {
        urls[productId] ?? GameCatalog.game(id: productId)?.posterURL
    }

    func clear() {
        fetchGeneration &+= 1
        urls.removeAll(keepingCapacity: true)
        inflight.removeAll(keepingCapacity: true)
    }

    func prefetch(_ ids: [String]) {
        let missing = Array(Set(ids.filter { !$0.isEmpty && urls[$0] == nil && !inflight.contains($0) }))
        missing.forEach { inflight.insert($0) }
        guard !missing.isEmpty else { return }
        let generation = fetchGeneration
        Task { await fetchBatch(missing, generation: generation) }
    }

    func load(_ productId: String) {
        prefetch([productId])
    }

    private func fetchBatch(_ ids: [String], generation: Int) async {
        defer {
            if generation == fetchGeneration {
                ids.forEach { inflight.remove($0) }
            }
        }
        let joined = ids.joined(separator: ",")
        guard let endpoint = URL(string: "https://displaycatalog.mp.microsoft.com/v7.0/products?bigIds=\(joined)&market=US&languages=en-US") else {
            return
        }
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard generation == fetchGeneration else { return }
            let parsed = Self.parseAllPosters(from: data)
            for (id, url) in parsed where urls[id] != url {
                urls[id] = url
            }
            for id in ids where urls[id] == nil {
                guard generation == fetchGeneration else { return }
                if let single = await fetchOne(id) {
                    guard generation == fetchGeneration else { return }
                    urls[id] = single
                }
            }
        } catch {
            guard generation == fetchGeneration else { return }
            for id in ids where urls[id] == nil {
                guard generation == fetchGeneration else { return }
                if let single = await fetchOne(id) {
                    guard generation == fetchGeneration else { return }
                    urls[id] = single
                }
            }
        }
    }

    private func fetchOne(_ productId: String) async -> URL? {
        guard let endpoint = URL(string: "https://displaycatalog.mp.microsoft.com/v7.0/products/\(productId)?market=US&languages=en-US") else {
            return nil
        }
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return Self.parsePoster(from: data)
        } catch {
            return nil
        }
    }

    static func parsePoster(from data: Data) -> URL? {
        parseAllPosters(from: data).values.first
    }

    static func parseAllPosters(from data: Data) -> [String: URL] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var products: [[String: Any]] = []
        if let list = json["Products"] as? [[String: Any]] {
            products = list
        } else if json["LocalizedProperties"] != nil {
            products = [json]
        }

        var out: [String: URL] = [:]
        for product in products {
            let pid = (product["ProductId"] as? String) ?? (product["productId"] as? String)
            guard let images = extractImages(from: product), let url = pickPoster(from: images) else { continue }
            if let pid { out[pid] = url }
            else if out.isEmpty { out["_"] = url }
        }
        return out
    }

    private static func extractImages(from product: [String: Any]) -> [[String: Any]]? {
        if let localized = product["LocalizedProperties"] as? [[String: Any]],
           let props = localized.first,
           let images = props["Images"] as? [[String: Any]] {
            return images
        }
        if let images = product["Images"] as? [[String: Any]] {
            return images
        }
        return nil
    }

    private static func pickPoster(from images: [[String: Any]]) -> URL? {
        let preferred = ["Poster", "BoxArt", "BrandedKeyArt", "TitledHeroArt", "SuperHeroArt", "FeaturePromotionalSquareArt", "Screenshot"]
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
