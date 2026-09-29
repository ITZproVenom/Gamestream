import Foundation
import Combine

/// Fetches the Xbox Cloud Gaming catalog.
///
/// The list of playable IDs comes from the Game Pass "sigl" feed, and the
/// details come from Microsoft's display catalog. The detail requests run
/// concurrently rather than one page after another; 1.x fetched ten pages in
/// series with a fifteen second timeout each, which is why the first launch
/// sat on a spinner for so long.
@MainActor
final class Catalog: ObservableObject {
    static let shared = Catalog()

    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var updatedAt: Date?

    private static let siglURL = URL(
        string: "https://catalog.gamepass.com/sigls/v2"
        + "?id=29a81209-df6f-41fd-a528-2ae6b91f719c&language=en-us&market=US"
    )!
    /// The catalog runs to a few hundred entries with artwork URLs, which is
    /// far too large for UserDefaults; that store is loaded whole on launch.
    private static let cacheURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("catalog-v1.json")
    }()
    private static let pageSize = 40

    private var task: Task<Void, Never>?
    private let log = AppLog.shared

    private init() {
        // Show the previous catalog immediately; a cold start should never be
        // an empty screen just because the network is slow.
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode([Game].self, from: data) {
            games = cached
            updatedAt = (try? Self.cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        }
    }

    var genres: [String] {
        Array(Set(games.map(\.genre))).sorted()
    }

    func games(inGenre genre: String) -> [Game] {
        games.filter { $0.genre == genre }
    }

    func game(id: String) -> Game? {
        games.first { $0.matches(id: id) }
    }

    func search(_ query: String) -> [Game] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        // Title matches first: someone typing "halo" wants the game, not every
        // shooter whose description mentions it.
        let byTitle = games.filter { $0.title.lowercased().contains(needle) }
        let byOther = games.filter {
            !$0.title.lowercased().contains(needle)
                && ($0.genre.lowercased().contains(needle)
                    || $0.tagline.lowercased().contains(needle))
        }
        return byTitle + byOther
    }

    /// Awaitable so pull-to-refresh keeps its spinner until the work is done.
    func refresh() async {
        task?.cancel()
        let task = Task { await load() }
        self.task = task
        await task.value
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let ids = try await fetchIDs()
            log.debug("catalog", "\(ids.count) product ids")
            let fetched = try await fetchDetails(ids: ids)
            guard !Task.isCancelled else { return }
            guard !fetched.isEmpty else { throw URLError(.cannotParseResponse) }

            games = fetched
            updatedAt = Date()
            if let data = try? JSONEncoder().encode(fetched) {
                try? data.write(to: Self.cacheURL, options: .atomic)
            }
            log.info("catalog", "loaded \(fetched.count) games")
        } catch is CancellationError {
        } catch {
            // Keep whatever is already on screen; an error banner beats
            // replacing a usable catalog with nothing.
            errorMessage = error.localizedDescription
            log.warn("catalog", "refresh failed: \(error.localizedDescription)")
        }
    }

    private func fetchIDs() async throws -> [String] {
        var request = URLRequest(url: Self.siglURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var seen = Set<String>()
        return rows.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty,
                  seen.insert(id.uppercased()).inserted else { return nil }
            return id
        }
    }

    private func fetchDetails(ids: [String]) async throws -> [Game] {
        let pages = stride(from: 0, to: ids.count, by: Self.pageSize).map { start in
            Array(ids[start..<min(start + Self.pageSize, ids.count)])
        }

        // Ordered results, fetched in parallel. The index keeps the catalog in
        // the order Microsoft returned it, which is roughly editorial order.
        var collected = [Int: [Game]]()
        try await withThrowingTaskGroup(of: (Int, [Game]).self) { group in
            for (index, page) in pages.enumerated() {
                group.addTask {
                    let games = await Self.fetchPage(page)
                    return (index, games)
                }
            }
            for try await (index, games) in group {
                collected[index] = games
            }
        }

        var output: [Game] = []
        var seen = Set<String>()
        for index in pages.indices {
            for game in collected[index] ?? [] where seen.insert(game.id.uppercased()).inserted {
                output.append(game)
            }
        }
        return output
    }

    private static func fetchPage(_ ids: [String]) async -> [Game] {
        var components = URLComponents(string: "https://displaycatalog.mp.microsoft.com/v7.0/products")
        components?.queryItems = [
            URLQueryItem(name: "bigIds", value: ids.joined(separator: ",")),
            URLQueryItem(name: "market", value: "US"),
            URLQueryItem(name: "languages", value: "en-us"),
            URLQueryItem(name: "fieldsTemplate", value: "Details")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("DGU1mcuYo0WMMp+F.1", forHTTPHeaderField: "MS-CV")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["Products"] as? [[String: Any]] else {
            return []
        }
        return products.compactMap(game(from:))
    }

    private static func game(from product: [String: Any]) -> Game? {
        guard let id = product["ProductId"] as? String, !id.isEmpty else { return nil }
        let localized = (product["LocalizedProperties"] as? [[String: Any]])?.first ?? [:]
        let title = ((localized["ProductTitle"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 2 else { return nil }

        let tagline = ((localized["ShortDescription"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let properties = product["Properties"] as? [String: Any] ?? [:]
        let rawGenre = (properties["Category"] as? String)
            ?? (properties["Categories"] as? [String])?.first
            ?? ""
        let images = localized["Images"] as? [[String: Any]] ?? []

        return Game(
            id: id,
            title: title,
            tagline: String(tagline.prefix(200)),
            genre: genre(from: rawGenre),
            posterURL: image(from: images, purposes: ["Poster", "BoxArt", "BrandedKeyArt"]),
            heroURL: image(from: images, purposes: ["SuperHeroArt", "TitledHeroArt", "FeaturePromotionalSquareArt"])
        )
    }

    private static func image(from images: [[String: Any]], purposes: [String]) -> URL? {
        for purpose in purposes {
            if let row = images.first(where: { ($0["ImagePurpose"] as? String) == purpose }),
               let raw = row["Uri"] as? String, let url = normalised(raw) {
                return url
            }
        }
        return images.compactMap { $0["Uri"] as? String }.compactMap(normalised).first
    }

    private static func normalised(_ raw: String) -> URL? {
        URL(string: raw.hasPrefix("//") ? "https:" + raw : raw)
    }

    /// Microsoft's categories are inconsistent, so they are folded into a small
    /// set of names that are actually useful as filters.
    private static func genre(from raw: String) -> String {
        let value = raw.lowercased()
        if value.contains("race") || value.contains("driv") { return "Racing" }
        if value.contains("shoot") { return "Shooter" }
        if value.contains("role") || value.contains("rpg") { return "RPG" }
        if value.contains("sport") { return "Sports" }
        if value.contains("strategy") { return "Strategy" }
        if value.contains("sim") { return "Simulation" }
        if value.contains("puzzle") || value.contains("word") { return "Puzzle" }
        if value.contains("advent") { return "Adventure" }
        if value.contains("platform") { return "Platformer" }
        if value.contains("fight") { return "Fighting" }
        if value.contains("family") || value.contains("kids") { return "Family" }
        if value.contains("card") || value.contains("board") { return "Card & Board" }
        if value.contains("action") { return "Action" }
        if value.contains("horror") { return "Horror" }
        if value.contains("indie") { return "Indie" }
        return raw.isEmpty ? "Other" : raw
    }
}
