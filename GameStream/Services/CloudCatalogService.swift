import Foundation

enum CloudCatalogService {
    private static let siglURL = URL(string: "https://catalog.gamepass.com/sigls/v2?id=29a81209-df6f-41fd-a528-2ae6b91f719c&language=en-us&market=US")!
    private static let cacheName = "xcloud-catalog-v2.json"
    private static var started = false

    static func refreshIfNeeded() {
        guard !started else { return }
        started = true
        Task { @MainActor in
            if let cached = loadCache(), cached.count >= 20 {
                GameCatalog.installLiveCatalog(cached)
            }
        }
        Task.detached(priority: .utility) {
            do {
                try await fetchRemoteProgressive()
            } catch {
            }
        }
    }

    private static func fetchRemoteProgressive() async throws {
        var request = URLRequest(url: siglURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let ids = parseIds(from: data)
        guard ids.count >= 20 else { return }

        var collected: [CatalogGame] = []
        collected.reserveCapacity(ids.count)
        let chunk = 20
        var index = 0
        var published = false
        while index < ids.count {
            let end = min(index + chunk, ids.count)
            let slice = Array(ids[index..<end])
            index = end
            do {
                collected.append(contentsOf: try await hydrate(slice))
            } catch {
                continue
            }
            if !published && collected.count >= 24 {
                let snapshot = collected
                await MainActor.run {
                    GameCatalog.installLiveCatalog(snapshot)
                }
                published = true
            }
        }
        let unique = dedupe(collected)
        guard unique.count >= 20 else { return }
        saveCache(unique)
        await MainActor.run {
            GameCatalog.installLiveCatalog(unique)
        }
    }

    private static func parseIds(from data: Data) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        func take(_ id: String) {
            let key = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            ids.append(id.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let rows = raw as? [[String: Any]] {
            for row in rows {
                if let id = row["id"] as? String { take(id) }
            }
        } else if let dict = raw as? [String: Any] {
            if let rows = dict["sigls"] as? [[String: Any]] {
                for row in rows {
                    if let id = row["id"] as? String { take(id) }
                }
            }
        }
        return ids
    }

    private static func hydrate(_ ids: [String]) async throws -> [CatalogGame] {
        let joined = ids.joined(separator: ",")
        guard let url = URL(string: "https://displaycatalog.mp.microsoft.com/v7.0/products?bigIds=\(joined)&market=US&languages=en-us&MS-CV=GS.1") else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
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
            out.append(
                CatalogGame(
                    id: id,
                    slug: slugify(title),
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
                return normalizedImageURL(raw)
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

    private static func dedupe(_ incoming: [CatalogGame]) -> [CatalogGame] {
        var seen = Set<String>()
        var out: [CatalogGame] = []
        for game in incoming {
            let key = game.id.uppercased()
            if seen.insert(key).inserted {
                out.append(game)
            }
        }
        return out
    }

    private static func cacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheName)
    }

    static func clearDiskCache() {
        guard let url = cacheURL() else { return }
        try? FileManager.default.removeItem(at: url)
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
