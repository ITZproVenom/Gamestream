import UIKit
import CryptoKit

/// Two-level artwork cache: memory, then disk, then the network.
///
/// Every step that touches the file system runs off the main actor. In 1.x the
/// cache was a `@MainActor` type that read files with `Data(contentsOf:)`, so
/// scrolling a grid of posters performed synchronous disk reads on the main
/// thread and the interface stuttered.
actor PosterCache {
    static let shared = PosterCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let directory: URL
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    /// Invalidates downloads that began before the user cleared the cache.
    private var clearGeneration = 0
    /// How much artwork is kept on disk.
    ///
    /// The posters are large - a few hundred thousand bytes each - and a
    /// catalogue of five hundred titles is a hundred megabytes of files
    /// that were never tidied away. The cache now keeps itself to a size.
    private let diskLimit = 240 * 1024 * 1024

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Posters", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 240
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }

        // Coalesce concurrent requests for the same artwork; a grid asks for
        // the same poster from several cells at once while scrolling.
        if let existing = inFlight[url] { return await existing.value }

        let generation = clearGeneration
        let task = Task<UIImage?, Never> { [directory] in
            let file = Self.fileURL(for: url, in: directory)
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                return image
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            guard generation == clearGeneration, !Task.isCancelled else { return nil }
            try? data.write(to: file, options: .atomic)
            // The cache is tidied as it grows, rather than waiting for the
            // player to clear it by hand.
            trimDiskIfNeeded()
            return image
        }

        inFlight[url] = task
        let image = await task.value
        guard generation == clearGeneration else { return image }
        inFlight[url] = nil
        if let image {
            // Without a cost the total cost limit never applies and the cache
            // is bounded only by its count, which for artwork is the
            // difference between 64 MB and several hundred.
            memory.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
        }
        return image
    }

    /// Roughly the decoded size in bytes.
    private static func cost(of image: UIImage) -> Int {
        let pixels = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
        return max(1, pixels * 4)
    }

    /// Removes the oldest artwork until the cache is back under its limit.
    private func trimDiskIfNeeded() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey, .creationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, size: Int, date: Date)] = []
        var total = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            let size = values.fileSize ?? 0
            total += size
            let date = values.contentAccessDate ?? values.creationDate ?? .distantPast
            entries.append((file, size, date))
        }
        guard total > diskLimit else { return }
        // The least recently used go first.
        entries.sort { $0.date < $1.date }
        for entry in entries {
            guard total > diskLimit else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
        AppLog.shared.info("cache", "the artwork cache was tidied back to its limit")
    }

    func clear() {
        clearGeneration &+= 1
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func diskUsage() -> Int {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)
        ) else { return 0 }
        return contents.reduce(0) { total, file in
            total + ((try? file.resourceValues(forKeys: keys).fileSize) ?? 0)
        }
    }

    private static func fileURL(for url: URL, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("img")
    }
}
