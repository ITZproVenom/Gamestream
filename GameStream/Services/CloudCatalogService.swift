import Foundation

enum CloudCatalogService {
    private static let siglURL = URL(string: "https://catalog.gamepass.com/sigls/v2?id=29a81209-df6f-41fd-a528-2ae6b91f719c&language=en-us&market=US")!
    private static let cacheName = "xcloud-catalog-v1.json"
    private static var started = false

    static func refreshIfNeeded() {
        guard !started else { return }
        started = true
        if let cached = loadCache(), cached.count >= 20 {
            GameCatalog.installLiveCatalog(cached)
        }
        Task.detached(priority: .utility) {
            do {
                let remote = try await fetchRemote()
                if remote.count >= 20 {
                    saveCache(remote)
                    GameCatalog.installLiveCatalog(remote)
                }
            } catch {
            }
        }
    }

    private static func fetchRemote() async throws -> [CatalogGame] {
        let (data, _) = try await URLSession.shared.data(from: siglURL)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var ids: [String] = []
        var seen = Set<String>()
        for row in raw {
            guard let id = row["id"] as? String else { continue }
            let key = id.uppercased()
            if seen.insert(key).inserted { ids.append(id) }
        }
        var games: [CatalogGame] = []
        let chunk = 20
        var index = 0
        while index < ids.count {
            let slice = Array(ids[index..<min(index + chunk, ids.count)])
            index += chunk
            games.append(contentsOf: try await hydrate(slice))
        }
        return games
    }

    private static func hydrate(_ ids: [String]) async throws -> [CatalogGame] {
        let joined = ids.joined(separator: ",")
        guard let url = URL(string: "https://displaycatalog.mp.microsoft.com/v7.0/products?bigIds=\(joined)&market=US&languages=en-us&MS-CV=GS.1") else {
            return []
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let products = json["Products"] as? [[String: Any]]
        else { return [] }

        var out: [CatalogGame] = []
        for product in products {
            guard let id = product["ProductId"] as? String, !id.isEmpty else { continue }
            let loc = (product["LocalizedProperties"] as? [[String: Any]])?.first
            let title = (loc?["ProductTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? id
            let tagline = (loc?["ShortDescription"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let props = product["Properties"] as? [String: Any]
            let genre = (props?["Category"] as? String)
                ?? ((props?["Categories"] as? [String])?.first)
                ?? "Cloud"
            let images = loc?["Images"] as? [[String: Any]] ?? []
            let poster = pickPoster(images)
            let slug = slugify(title)
            out.append(
                CatalogGame(
                    id: id,
                    slug: slug,
                    title: title,
                    tagline: String(tagline.prefix(140)),
                    genre: shortenGenre(genre),
                    provider: "Xbox Cloud",
                    featured: false,
                    accent: 0x4361EE,
                    posterURL: poster
                )
            )
        }
        return out
    }

    private static func pickPoster(_ images: [[String: Any]]) -> URL? {
        let preferred = ["Poster", "BoxArt", "BrandedKeyArt", "TitledHeroArt", "SuperHeroArt"]
        for purpose in preferred {
            if let match = images.first(where: { ($0["ImagePurpose"] as? String) == purpose }),
               let raw = match["Uri"] as? String {
                if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
                return URL(string: raw)
            }
        }
        if let raw = images.first?["Uri"] as? String {
            if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
            return URL(string: raw)
        }
        return nil
    }

    private static func slugify(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = CharacterSet.alphanumerics
        var slug = ""
        var dash = false
        for scalar in lowered.unicodeScalars {
            if allowed.contains(scalar) {
                slug.append(Character(scalar))
                dash = false
            } else if !dash {
                slug.append("-")
                dash = true
            }
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func shortenGenre(_ raw: String) -> String {
        let value = raw.lowercased()
        if value.contains("race") { return "Racing" }
        if value.contains("shoot") { return "Shooter" }
        if value.contains("rpg") || value.contains("role") { return "RPG" }
        if value.contains("platform") { return "Platformer" }
        if value.contains("sandbox") { return "Sandbox" }
        if value.contains("surviv") { return "Survival" }
        if value.contains("sport") { return "Sports" }
        if value.contains("fight") { return "Fighting" }
        if value.contains("sim") { return "Simulation" }
        if value.contains("strat") { return "Strategy" }
        if value.contains("puzzle") { return "Puzzle" }
        if value.contains("adventure") { return "Adventure" }
        if value.contains("action") { return "Action" }
        return raw
    }

    private static func cacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheName)
    }

    private static func saveCache(_ games: [CatalogGame]) {
        guard let url = cacheURL() else { return }
        let payload: [[String: String]] = games.map { game in
            [
                "id": game.id,
                "slug": game.slug,
                "title": game.title,
                "tagline": game.tagline,
                "genre": game.genre,
                "poster": game.posterURL?.absoluteString ?? ""
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func loadCache() -> [CatalogGame]? {
        guard
            let url = cacheURL(),
            let data = try? Data(contentsOf: url),
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return nil }
        var seen = Set<String>()
        var games: [CatalogGame] = []
        for row in rows {
            guard let id = row["id"], seen.insert(id.uppercased()).inserted else { continue }
            let poster = row["poster"].flatMap { $0.isEmpty ? nil : URL(string: $0) }
            games.append(
                CatalogGame(
                    id: id,
                    slug: row["slug"] ?? id.lowercased(),
                    title: row["title"] ?? id,
                    tagline: row["tagline"] ?? "",
                    genre: row["genre"] ?? "Cloud",
                    provider: "Xbox Cloud",
                    featured: false,
                    accent: 0x4361EE,
                    posterURL: poster
                )
            )
        }
        return games
    }
}
