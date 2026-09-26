import Foundation
import Combine
import WebKit

struct TrackedGame: Codable, Identifiable, Hashable, Equatable {
    let id: String
    var slug: String
    var title: String
    var lastSeen: Date
    var isFavorite: Bool

    var catalogURL: URL? {
        let safeSlug = slug.isEmpty ? id.lowercased() : slug
        return URL(string: "https://www.xbox.com/play/games/\(safeSlug)/\(id)")
    }

    var launchURL: URL? {
        let safeSlug = slug.isEmpty ? id.lowercased() : slug
        return URL(string: "https://www.xbox.com/play/launch/\(safeSlug)/\(id)")
    }
}

struct PlayRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let gameID: String
    let title: String
    let startedAt: Date
    var seconds: TimeInterval
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var accountLabel: String?
    @Published var webURL: URL
    @Published var isStreaming = false
    @Published var pendingJavaScript: String?
    @Published var betterXCloudRefreshToken = 0
    @Published var reloadNonce = 0
    @Published var favorites: [TrackedGame] = []
    @Published var recents: [TrackedGame] = []
    @Published var queue: [TrackedGame] = []
    @Published private(set) var playRecords: [PlayRecord] = []
    @Published var currentGame: TrackedGame?

    private var streamStartedAt: Date?

    private enum Key {
        static let signedIn = "GameStream.session.signedIn"
        static let account = "GameStream.session.account"
        static let proof = MicrosoftAuth.proofKey
        static let favorites = "GameStream.session.favorites.v3"
        static let recents = "GameStream.session.recents.v3"
        static let queue = "GameStream.session.queue.v2"
        static let playRecords = "GameStream.session.playRecords.v1"
        static let keepAwake = "GameStream.settings.keepAwake.v1"
        static let resolution = "GameStream.settings.resolution.v1"
        static let region = "GameStream.settings.region.v1"
        static let betterPrefs = "BetterXCloud.prefs.v1"
    }

    init() {
        let proof = UserDefaults.standard.integer(forKey: Key.proof)
        let stored = UserDefaults.standard.bool(forKey: Key.signedIn)
        isSignedIn = stored && proof == MicrosoftAuth.proofVersion
        accountLabel = UserDefaults.standard.string(forKey: Key.account)
        favorites = Self.load([TrackedGame].self, key: Key.favorites) ?? []
        recents = Self.load([TrackedGame].self, key: Key.recents) ?? []
        queue = Self.load([TrackedGame].self, key: Key.queue) ?? []
        playRecords = Self.load([PlayRecord].self, key: Key.playRecords) ?? []
        webURL = MicrosoftAuth.playURL
        rehydrateFlags()
    }

    func markSignedInAfterMicrosoftAuth(as label: String = "Xbox Account") {
        UserDefaults.standard.set(MicrosoftAuth.proofVersion, forKey: Key.proof)
        UserDefaults.standard.set(true, forKey: Key.signedIn)
        UserDefaults.standard.set(label, forKey: Key.account)
        accountLabel = label
        isSignedIn = true
    }

    func revalidatePersistedLogin() {
        guard isSignedIn else { return }
        MicrosoftAuth.fetchAuthCookies { [weak self] cookies in
            guard let self else { return }
            if !MicrosoftAuth.cookiesIndicateXboxSession(cookies) {
                Task { @MainActor in self.clearAuthenticationState() }
            }
        }
    }

    func signOut() {
        exitStreamToHub()
        clearAuthenticationState()
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let matching = records.filter {
                let name = $0.displayName.lowercased()
                return name.contains("xbox") || name.contains("microsoft") || name.contains("live") || name.contains("bing")
            }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matching) {}
        }
    }

    private func clearAuthenticationState() {
        UserDefaults.standard.set(false, forKey: Key.signedIn)
        UserDefaults.standard.removeObject(forKey: Key.account)
        UserDefaults.standard.removeObject(forKey: Key.proof)
        isSignedIn = false
        accountLabel = nil
        isStreaming = false
        currentGame = nil
    }

    func play(_ game: TrackedGame) {
        guard let url = game.launchURL else { return }
        var played = game
        played.lastSeen = Date()
        played.isFavorite = isFavorite(game.id)

        recents.removeAll { $0.id.caseInsensitiveCompare(game.id) == .orderedSame }
        recents.insert(played, at: 0)
        recents = Array(recents.prefix(20))
        persist(recents, key: Key.recents)

        currentGame = played
        webURL = url
        streamStartedAt = Date()
        isStreaming = true
    }

    func exitStreamToHub() {
        finishPlayRecordIfNeeded()
        isStreaming = false
        streamStartedAt = nil
        webURL = MicrosoftAuth.playURL
        currentGame = nil
    }

    func returnToHub() {
        finishPlayRecordIfNeeded()
        isStreaming = false
        streamStartedAt = nil
        webURL = MicrosoftAuth.playURL
    }

    func playNextFromStream() {
        guard let first = queue.first else {
            exitStreamToHub()
            return
        }
        queue.removeFirst()
        persist(queue, key: Key.queue)
        play(first)
    }

    func toggleFavorite(_ game: TrackedGame) {
        if let index = favorites.firstIndex(where: { $0.id.caseInsensitiveCompare(game.id) == .orderedSame }) {
            favorites.remove(at: index)
        } else {
            var pinned = game
            pinned.isFavorite = true
            pinned.lastSeen = Date()
            favorites.insert(pinned, at: 0)
        }
        favorites = Array(favorites.prefix(50))
        persist(favorites, key: Key.favorites)
        refreshCurrentFavoriteFlag()
    }

    func toggleFavoriteCurrent() {
        guard let currentGame else { return }
        toggleFavorite(currentGame)
    }

    func isFavorite(_ id: String) -> Bool {
        favorites.contains { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    func toggleQueue(_ game: TrackedGame) {
        if isQueued(game.id) {
            queue.removeAll { $0.id.caseInsensitiveCompare(game.id) == .orderedSame }
        } else {
            queue.append(game)
        }
        queue = Array(queue.suffix(20))
        persist(queue, key: Key.queue)
    }

    func isQueued(_ id: String) -> Bool {
        queue.contains { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    func dequeue(_ game: TrackedGame) {
        queue.removeAll { $0.id.caseInsensitiveCompare(game.id) == .orderedSame }
        persist(queue, key: Key.queue)
    }

    func clearFavorites() {
        favorites.removeAll()
        persist(favorites, key: Key.favorites)
        refreshCurrentFavoriteFlag()
    }

    func clearRecents() {
        recents.removeAll()
        persist(recents, key: Key.recents)
    }

    func openXboxCloud() {
        webURL = MicrosoftAuth.playURL
        isStreaming = false
        currentGame = nil
        reloadNonce &+= 1
    }

    func reloadCurrent() {
        reloadNonce &+= 1
    }

    func applyStreamResolution(_ resolution: String) {
        UserDefaults.standard.set(resolution, forKey: Key.resolution)
        applyBetterXCloudPref("stream.video.resolution", value: resolution == "1080p HQ" ? "1080p-hq" : resolution.lowercased())
    }

    func applyServerRegion(_ region: String) {
        UserDefaults.standard.set(region, forKey: Key.region)
        let mapped: String
        switch region {
        case "North America": mapped = "us"
        case "Europe": mapped = "eu"
        case "Asia": mapped = "jp"
        case "Australia": mapped = "au"
        default: mapped = ""
        }
        applyBetterXCloudPref("server.region", value: mapped)
    }

    func refreshBetterXCloudScript() {
        BetterXCloudInjector.shared.invalidateCache()
        UserDefaults.standard.removeObject(forKey: "BetterXCloud.Script.v2")
        UserDefaults.standard.removeObject(forKey: "BetterXCloud.Script.Date.v2")
        betterXCloudRefreshToken &+= 1
        if webURL.host?.contains("xbox.com") == true {
            pendingJavaScript = "try { location.reload(); } catch (e) {}"
        }
    }

    func applyBetterXCloudPref(_ prefKey: String, value: String) {
        var map = Self.storedBetterXCloudPrefs()
        map[prefKey] = value
        UserDefaults.standard.set(map, forKey: Key.betterPrefs)
        if webURL.host?.contains("xbox.com") == true {
            pendingJavaScript = Self.betterXCloudPrefsJS(map, reloadIfXbox: true)
        }
    }

    static func storedBetterXCloudPrefs() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: Key.betterPrefs) as? [String: String]) ?? [:]
    }

    static func betterXCloudPrefsJS(_ map: [String: String], reloadIfXbox: Bool) -> String {
        let pairs = map.map { key, value in
            let safeKey = key
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let safeValue = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            return "data['\(safeKey)']='\(safeValue)'; try { localStorage.setItem('BetterXcloud.\(safeKey)', '\(safeValue)'); } catch (e) {}"
        }
        let body = pairs.joined(separator: "\n")
        let reload = reloadIfXbox ? "if (/xbox\\.com/i.test(location.host)) { setTimeout(function(){ location.reload(); }, 80); }" : ""
        return """
        (function() {
            try {
                if (!location.host || location.host.indexOf('xbox.com') === -1) return;
                var storageKey = 'BetterXcloud';
                var data = {};
                try { data = JSON.parse(localStorage.getItem(storageKey) || '{}') || {}; } catch (e) { data = {}; }
                \(body)
                localStorage.setItem(storageKey, JSON.stringify(data));
                \(reload)
            } catch (e) {}
        })();
        """
    }

    var keepScreenAwake: Bool {
        get { UserDefaults.standard.bool(forKey: Key.keepAwake) }
        set { UserDefaults.standard.set(newValue, forKey: Key.keepAwake) }
    }

    var storedResolution: String {
        UserDefaults.standard.string(forKey: Key.resolution) ?? "Auto"
    }

    var storedRegion: String {
        UserDefaults.standard.string(forKey: Key.region) ?? "Auto"
    }

    private func refreshCurrentFavoriteFlag() {
        guard let currentGame else { return }
        var updated = currentGame
        updated.isFavorite = isFavorite(updated.id)
        self.currentGame = updated
    }

    private func finishPlayRecordIfNeeded() {
        guard let game = currentGame, let started = streamStartedAt else { return }
        let seconds = max(0, Date().timeIntervalSince(started))
        guard seconds >= 5 else { return }
        let record = PlayRecord(
            id: UUID(),
            gameID: game.id,
            title: game.title,
            startedAt: started,
            seconds: seconds
        )
        playRecords.insert(record, at: 0)
        playRecords = Array(playRecords.prefix(200))
        persist(playRecords, key: Key.playRecords)
    }

    private func rehydrateFlags() {
        favorites = favorites.map { game in
            var copy = game
            copy.isFavorite = true
            return copy
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
