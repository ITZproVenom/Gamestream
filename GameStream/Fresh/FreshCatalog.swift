import Foundation
import SwiftUI

struct FreshGame: Identifiable, Hashable, Codable {
    let id: String
    let slug: String
    let title: String
    let tagline: String
    let genre: String
    let posterURL: URL?

    var tracked: TrackedGame {
        TrackedGame(id: id, slug: slug, title: title, lastSeen: Date(), isFavorite: false)
    }
}

@MainActor
final class FreshCatalogStore: ObservableObject {
    static let shared = FreshCatalogStore()

    @Published private(set) var games: [FreshGame] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var updatedAt: Date?

    private var loadTask: Task<Void, Never>?
    private let endpoint = URL(string: "https://catalog.gamepass.com/sigls/v2?id=29a81209-df6f-41fd-a528-2ae6b91f719c&language=en-us&market=US")!

    private init() {
        loadTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    deinit {
        loadTask?.cancel()
    }

    func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
        }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            let ids = try await fetchIDs()
            let hydrated = try await hydrate(ids: ids)
            let unique = Self.dedupe(hydrated)
            guard !unique.isEmpty else { throw URLError(.cannotParseResponse) }

            games = unique
            updatedAt = Date()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchIDs() async throws -> [String] {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)

        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var seen = Set<String>()
        return raw.compactMap { row in
            guard let value = row["id"] as? String, !value.isEmpty else { return nil }
            let key = value.uppercased()
            guard seen.insert(key).inserted else { return nil }
            return value
        }
    }

    private func hydrate(ids: [String]) async throws -> [FreshGame] {
        var output: [FreshGame] = []
        output.reserveCapacity(ids.count)

        for start in stride(from: 0, to: ids.count, by: 40) {
            let end = min(start + 40, ids.count)
            let page = Array(ids[start..<end])
            guard !page.isEmpty else { continue }

            var components = URLComponents(string: "https://displaycatalog.mp.microsoft.com/v7.0/products")!
            components.queryItems = [
                URLQueryItem(name: "bigIds", value: page.joined(separator: ",")),
                URLQueryItem(name: "market", value: "US"),
                URLQueryItem(name: "languages", value: "en-us"),
                URLQueryItem(name: "MS-CV", value: "DGU1mcuYo0WMMp+F.1"),
                URLQueryItem(name: "fieldsTemplate", value: "Details")
            ]

            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                continue
            }

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                continue
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let products = json["Products"] as? [[String: Any]]
            else { continue }

            for product in products {
                guard let id = product["ProductId"] as? String, !id.isEmpty else { continue }
                let localized = (product["LocalizedProperties"] as? [[String: Any]])?.first ?? [:]
                let title = ((localized["ProductTitle"] as? String) ?? id).trimmingCharacters(in: .whitespacesAndNewlines)
                guard title.count >= 2 else { continue }

                let tagline = ((localized["ShortDescription"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let properties = product["Properties"] as? [String: Any] ?? [:]
                let rawGenre = (properties["Category"] as? String)
                    ?? ((properties["Categories"] as? [String])?.first)
                    ?? "Cloud"

                let images = localized["Images"] as? [[String: Any]] ?? []
                output.append(
                    FreshGame(
                        id: id,
                        slug: Self.slugify(title),
                        title: title,
                        tagline: String(tagline.prefix(160)),
                        genre: Self.genre(rawGenre),
                        posterURL: Self.poster(from: images)
                    )
                )
            }
        }

        if output.isEmpty {
            return try await hydrateViaGamePass(ids: ids)
        }

        return output
    }

    private func hydrateViaGamePass(ids: [String]) async throws -> [FreshGame] {
        var output: [FreshGame] = []
        output.reserveCapacity(ids.count)

        for start in stride(from: 0, to: ids.count, by: 80) {
            let end = min(start + 80, ids.count)
            let page = Array(ids[start..<end])
            guard !page.isEmpty else { continue }

            guard let url = URL(string: "https://catalog.gamepass.com/v3/products?market=US&language=en-US&hydration=MobileDetailsForConsole") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Xbox/Shell/Http", forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["Products": page])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let products = json["Products"] as? [[String: Any]] else {
                continue
            }

            output.append(contentsOf: Self.games(from: products))
        }

        return Self.dedupe(output)
    }

    private static func games(from products: [[String: Any]]) -> [FreshGame] {
        products.compactMap { product in
            guard let id = (product["ProductId"] as? String) ?? (product["id"] as? String), !id.isEmpty else { return nil }
            let localized = (product["LocalizedProperties"] as? [[String: Any]])?.first ?? [:]
            let title = ((localized["ProductTitle"] as? String) ?? (product["title"] as? String) ?? id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 2 else { return nil }

            let tagline = ((localized["ShortDescription"] as? String) ?? (product["description"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let properties = product["Properties"] as? [String: Any] ?? [:]
            let rawGenre = (properties["Category"] as? String)
                ?? ((properties["Categories"] as? [String])?.first)
                ?? "Cloud"
            let images = localized["Images"] as? [[String: Any]] ?? []

            return FreshGame(
                id: id,
                slug: Self.slugify(title),
                title: title,
                tagline: String(tagline.prefix(160)),
                genre: Self.genre(rawGenre),
                posterURL: Self.poster(from: images)
            )
        }
    }

    func search(_ query: String) -> [FreshGame] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return games }

        return games.filter {
            $0.title.lowercased().contains(value)
                || $0.genre.lowercased().contains(value)
                || $0.tagline.lowercased().contains(value)
        }
    }

    func genreGames(_ genre: String) -> [FreshGame] {
        games.filter { $0.genre == genre }
    }

    var genres: [String] {
        Array(Set(games.map { $0.genre })).sorted()
    }

    var featured: [FreshGame] {
        Array(games.prefix(6))
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func dedupe(_ input: [FreshGame]) -> [FreshGame] {
        var seen = Set<String>()
        return input.filter { seen.insert($0.id.uppercased()).inserted }
    }

    private static func poster(from images: [[String: Any]]) -> URL? {
        let preferred = ["Poster", "BoxArt", "BrandedKeyArt", "TitledHeroArt", "SuperHeroArt"]
        for purpose in preferred {
            if let row = images.first(where: { ($0["ImagePurpose"] as? String) == purpose }),
               let raw = row["Uri"] as? String {
                return normalizedURL(raw)
            }
        }
        return images.compactMap { $0["Uri"] as? String }.compactMap(normalizedURL).first
    }

    private static func normalizedURL(_ raw: String) -> URL? {
        if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
        return URL(string: raw)
    }

    private static func slugify(_ value: String) -> String {
        var result = ""
        var needsDash = false

        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.append(String(scalar))
                needsDash = false
            } else if !needsDash {
                result.append("-")
                needsDash = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func genre(_ raw: String) -> String {
        let value = raw.lowercased()
        if value.contains("race") { return "Racing" }
        if value.contains("shoot") { return "Shooter" }
        if value.contains("role") || value.contains("rpg") { return "RPG" }
        if value.contains("sport") { return "Sports" }
        if value.contains("strategy") { return "Strategy" }
        if value.contains("sim") { return "Simulation" }
        if value.contains("puzzle") { return "Puzzle" }
        if value.contains("adventure") { return "Adventure" }
        if value.contains("platform") { return "Platformer" }
        if value.contains("fight") { return "Fighting" }
        if value.contains("action") { return "Action" }
        return raw.isEmpty ? "Cloud" : raw
    }
}

struct FreshList: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var gameIDs: [String]
}

@MainActor
final class FreshListsStore: ObservableObject {
    static let shared = FreshListsStore()

    @Published private(set) var lists: [FreshList] = []

    private let key = "GameStream.freshLists.v1"

    private init() {
        lists = Self.load(key: key)
    }

    func create(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lists.append(FreshList(id: UUID(), name: clean, gameIDs: []))
        persist()
    }

    func delete(_ list: FreshList) {
        lists.removeAll { $0.id == list.id }
        persist()
    }

    func toggle(game: String, in list: FreshList) {
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        if lists[index].gameIDs.contains(game) {
            lists[index].gameIDs.removeAll { $0 == game }
        } else {
            lists[index].gameIDs.append(game)
        }
        persist()
    }

    func contains(game: String, in list: FreshList) -> Bool {
        list.gameIDs.contains(game)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load(key: String) -> [FreshList] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([FreshList].self, from: data) else {
            return []
        }
        return value
    }
}
