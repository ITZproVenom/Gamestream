import Foundation
import UIKit
import CryptoKit
import ImageIO
import SwiftUI

/// Memory-cached, downsample-on-load image fetcher used instead of AsyncImage.
/// Microsoft store posters are multi-megapixel; AsyncImage re-downloads and
/// decodes every card at full resolution with no memory cache, which makes the
/// hub janky while scrolling. This loads each image once, decodes it to a small
/// thumbnail (we never display larger), and serves repeat requests synchronously
/// from NSCache. Network + downsample run off the main actor.
@MainActor
final class RemoteImageLoader: ObservableObject {
    static let shared = RemoteImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Bool] = [:]

    private static let diskDirectoryName = "GameStreamArtwork"
    private let fileManager = FileManager.default

    private var diskDirectory: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.diskDirectoryName, isDirectory: true)
    }

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 96 * 1024 * 1024
        try? diskDirectory.map { try fileManager.createDirectory(at: $0, withIntermediateDirectories: true) }
    }

    /// Synchronous cache hop for use from `body`; never performs network.
    func stored(_ url: URL?) -> UIImage? {
        guard let url else { return nil }
        return cache.object(forKey: url as NSURL)
    }

    /// Serves artwork from memory, then the persistent artwork cache, and only
    /// then downloads it. This keeps the GameHub fast across launches.
    func request(_ url: URL?) {
        guard let url else { return }
        guard inflight[url] == nil, stored(url) == nil else { return }
        inflight[url] = true

        Task { [weak self] in
            guard let self else { return }

            var image = await Self.loadDiskImage(url: url, directory: diskDirectory)

            if image == nil {
                image = await Self.image(for: url)
                if let image {
                    await Self.saveDiskImage(image, url: url, directory: diskDirectory)
                }
            }

            self.inflight[url] = nil
            if let image {
                let cost = Int(image.size.width * image.size.height * 4)
                self.cache.setObject(image, forKey: url as NSURL, cost: max(cost, 1))
            }
            NotificationCenter.default.post(name: .remoteImageLoaded, object: url)
        }
    }

    /// Clears both the in-memory and persistent poster caches. Settings > Clear
    /// cache calls this method, so the user controls both layers with one action.
    func clear() {
        cache.removeAllObjects()
        inflight.removeAll(keepingCapacity: true)
        if let directory = diskDirectory {
            try? fileManager.removeItem(at: directory)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    nonisolated private static func diskURL(for url: URL, directory: URL?) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("jpg")
    }

    nonisolated private static func loadDiskImage(url: URL, directory: URL?) async -> UIImage? {
        guard let path = diskURL(for: url, directory: directory),
              let data = try? Data(contentsOf: path),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    nonisolated private static func saveDiskImage(_ image: UIImage, url: URL, directory: URL?) async {
        guard let directory,
              let path = diskURL(for: url, directory: directory),
              let data = image.jpegData(compressionQuality: 0.86) else {
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: path, options: .atomic)
    }

    nonisolated private static func image(for url: URL) async -> UIImage? {
        guard let data = await data(for: url) else { return nil }
        return downsample(data, maxPixel: 720)
    }

    nonisolated private static func data(for url: URL) async -> Data? {
        (try? await URLSession.shared.data(from: url))?.0
    }

    /// ImageIO thumbnail: decodes to ~720px instead of the poster's full size.
    nonisolated private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Fetches one image via `RemoteImageLoader` and renders it filled to its frame.
/// Shows the placeholder until the image finishes decoding. Each instance reacts
/// only to its own URL completing, so one image loading never re-renders the
/// whole grid.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: UIImage?

    var body: some View {
        Group {
            if let image = loaded ?? RemoteImageLoader.shared.stored(url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .onAppear {
            RemoteImageLoader.shared.request(url)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .remoteImageLoaded)
                .compactMap { $0.object as? URL }
                .filter { url != nil && $0 == url! }
        ) { _ in
            loaded = RemoteImageLoader.shared.stored(url)
        }
    }
}

extension Notification.Name {
    static let remoteImageLoaded = Notification.Name("GameStreamRemoteImageLoaded")
}