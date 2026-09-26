import Foundation
import Combine
import WebKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var isSignedIn: Bool {
        didSet { UserDefaults.standard.set(isSignedIn, forKey: Keys.signedIn) }
    }

    @Published var accountLabel: String? {
        didSet { UserDefaults.standard.set(accountLabel, forKey: Keys.accountLabel) }
    }

    @Published var webURL: URL = URL(string: "about:blank")!
    @Published var requestedTab: RootView.Tab? = nil
    @Published var isStreaming: Bool = false
    @Published var pendingJavaScript: String?
    @Published var betterXCloudRefreshToken: Int = 0
    @Published var reloadNonce: Int = 0
    @Published var searchDraft: String = ""
    @Published var keepScreenAwake: Bool {
        didSet { UserDefaults.standard.set(keepScreenAwake, forKey: Keys.keepScreenAwake) }
    }
    @Published var favorites: [TrackedGame] = []
    @Published var recents: [TrackedGame] = []
    @Published var currentGame: TrackedGame?
    @Published var offerPlayNext: Bool = false

    private enum Keys {
        static let signedIn = "GameStream.isSignedIn"
        static let accountLabel = "GameStream.accountLabel"
        static let streamResolution = "GameStream.streamResolution"
        static let serverRegion = "GameStream.serverRegion"
        static let recentSearches = "GameStream.recentSearches"
        static let searchDraft = "GameStream.searchDraft"
        static let keepScreenAwake = "GameStream.keepScreenAwake"
        static let favorites = "GameStream.favorites.v1"
        static let recents = "GameStream.recents.v1"
    }

    init() {
        let proof = UserDefaults.standard.integer(forKey: MicrosoftAuth.proofKey)
        let storedSignedIn = UserDefaults.standard.bool(forKey: Keys.signedIn)
        if storedSignedIn && proof != MicrosoftAuth.proofVersion {
            UserDefaults.standard.set(false, forKey: Keys.signedIn)
            UserDefaults.standard.removeObject(forKey: Keys.accountLabel)
            self.isSignedIn = false
            self.accountLabel = nil
        } else {
            self.isSignedIn = storedSignedIn && proof == MicrosoftAuth.proofVersion
            self.accountLabel = UserDefaults.standard.string(forKey: Keys.accountLabel)
        }
        self.searchDraft = UserDefaults.standard.string(forKey: Keys.searchDraft) ?? ""
        self.keepScreenAwake = UserDefaults.standard.bool(forKey: Keys.keepScreenAwake)
        self.favorites = Self.loadGames(key: Keys.favorites)
        self.recents = Self.loadGames(key: Keys.recents)
        // Always start non-streaming — a prior force-quit can leave UI state inconsistent.
        self.isStreaming = false
        self.offerPlayNext = false
        self.currentGame = nil
        self.webURL = Self.idleWebURL
        self.pendingJavaScript = nil
    }

    func updateSearchDraft(_ value: String) {
        searchDraft = value
        UserDefaults.standard.set(value, forKey: Keys.searchDraft)
    }

    func markSignedInAfterMicrosoftAuth(as label: String = "Xbox Account") {
        UserDefaults.standard.set(MicrosoftAuth.proofVersion, forKey: MicrosoftAuth.proofKey)
        self.accountLabel = label
        self.isSignedIn = true
    }

    func revalidatePersistedLogin() {
        guard isSignedIn else { return }
        MicrosoftAuth.fetchAuthCookies { cookies in
            Task { @MainActor in
                if !MicrosoftAuth.cookiesIndicateXboxSession(cookies) {
                    self.clearLocalAuthFlag()
                }
            }
        }
    }

    private func clearLocalAuthFlag() {
        isSignedIn = false
        accountLabel = nil
        UserDefaults.standard.removeObject(forKey: MicrosoftAuth.proofKey)
    }

    func signOut() {
        PlayActivityStore.shared.end()
        clearLocalAuthFlag()
        isStreaming = false
        offerPlayNext = false
        currentGame = nil
        webURL = Self.idleWebURL
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let xboxRecords = records.filter {
                let name = $0.displayName.lowercased()
                return name.contains("xbox") || name.contains("microsoft") || name.contains("live") || name.contains("bing")
            }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: xboxRecords) {}
        }
    }

    func openSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSearchDraft(trimmed)
        requestedTab = .search
    }

    func openHome() {
        returnToHub()
    }

    func openGame(_ game: TrackedGame) {
        requestedTab = .library
        HubState.shared.showNativeHub = true
        isStreaming = false
        offerPlayNext = false
        noteGame(id: game.id, slug: game.slug, title: game.title, markRecent: false)
    }

    func goBack() {
        returnToHub()
    }

    func reloadCurrent() { reloadNonce += 1 }

    func updateFromWebURL(_ url: URL, pageTitle: String? = nil) {
        let streaming = Self.isStreamingURL(url.absoluteString)
        if isStreaming && !streaming {
            return
        }
        if streaming {
            offerPlayNext = false
            if !isStreaming { isStreaming = true }
        }
        if let parsed = GameURLParser.parse(url.absoluteString) {
            let title = GameURLParser.displayTitle(fromPageTitle: pageTitle, slug: parsed.slug, productId: parsed.productId)
            noteGame(id: parsed.productId, slug: parsed.slug, title: title, markRecent: streaming)
        }
        syncPlayActivity(streaming: isStreaming)
    }

    func toggleFavoriteCurrent() { guard let game = currentGame else { return }; toggleFavorite(game) }

    func toggleFavorite(_ game: TrackedGame) {
        if let index = favorites.firstIndex(where: { $0.id == game.id }) {
            favorites.remove(at: index)
        } else {
            var pinned = game
            pinned.isFavorite = true
            pinned.lastSeen = Date()
            favorites.insert(pinned, at: 0)
        }
        if favorites.count > 24 { favorites = Array(favorites.prefix(24)) }
        persistFavorites()
        refreshCurrentFavoriteFlag()
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(where: { $0.id == id }) }
    func removeRecent(_ game: TrackedGame) {
        recents.removeAll { $0.id == game.id }
        persistRecents()
        if currentGame?.id == game.id { currentGame = recents.first }
    }
    func clearRecents() { recents = []; persistRecents() }
    func clearFavorites() { favorites = []; persistFavorites(); refreshCurrentFavoriteFlag() }

    private func noteGame(id: String, slug: String, title: String, markRecent: Bool) {
        guard !id.isEmpty else { return }
        var game = TrackedGame(id: id, slug: slug, title: title, lastSeen: Date(), isFavorite: isFavorite(id))
        if let existingFav = favorites.first(where: { $0.id == id }) {
            game.isFavorite = true
            if title.count >= existingFav.title.count {
                var updated = existingFav
                updated.title = title
                updated.slug = slug.isEmpty ? existingFav.slug : slug
                updated.lastSeen = Date()
                if let idx = favorites.firstIndex(where: { $0.id == id }) {
                    favorites[idx] = updated
                    persistFavorites()
                }
            }
        }
        currentGame = game
        guard markRecent else { return }
        recents.removeAll { $0.id == id }
        recents.insert(game, at: 0)
        if recents.count > 12 { recents = Array(recents.prefix(12)) }
        persistRecents()
    }

    private func refreshCurrentFavoriteFlag() {
        guard var game = currentGame else { return }
        game.isFavorite = isFavorite(game.id)
        currentGame = game
    }
    private func persistFavorites() { Self.saveGames(favorites, key: Keys.favorites) }
    private func persistRecents() { Self.saveGames(recents, key: Keys.recents) }
    private static func loadGames(key: String) -> [TrackedGame] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TrackedGame].self, from: data)) ?? []
    }
    private static func saveGames(_ games: [TrackedGame], key: String) {
        if let data = try? JSONEncoder().encode(games) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func isStreamingURL(_ raw: String) -> Bool {
        let full = raw.lowercased()
        if full.contains("/play/games") { return false }
        return full.contains("/play/launch") || full.contains("/launch/") || full.contains("/launch?") || full.contains("/stream/") || full.contains("/streaming")
    }

    static var recentSearches: [String] { UserDefaults.standard.stringArray(forKey: Keys.recentSearches) ?? [] }
    static func rememberSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        if items.count > 8 { items = Array(items.prefix(8)) }
        UserDefaults.standard.set(items, forKey: Keys.recentSearches)
    }
    static func clearRecentSearches() { UserDefaults.standard.removeObject(forKey: Keys.recentSearches) }

    private static let bxPrefsKey = "BetterXCloud.prefs.v1"

    static func storedBetterXCloudPrefs() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: bxPrefsKey) as? [String: String]) ?? [:]
    }

    static func betterXCloudPrefsJS(_ map: [String: String], reloadIfXbox: Bool) -> String {
        var pairs: [String] = []
        for (key, value) in map {
            let ek = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            let ev = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            pairs.append("data['\(ek)']='\(ev)'; try { localStorage.setItem('BetterXcloud.\(ek)', '\(ev)'); } catch (e) {}")
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

    func applyBetterXCloudPref(_ prefKey: String, value: String) {
        var map = Self.storedBetterXCloudPrefs()
        map[prefKey] = value
        UserDefaults.standard.set(map, forKey: Self.bxPrefsKey)
        if isStreaming, webURL.host?.contains("xbox.com") == true {
            pendingJavaScript = Self.betterXCloudPrefsJS(map, reloadIfXbox: true)
        }
    }

    func applyStreamResolution(_ resolution: String) {
        UserDefaults.standard.set(resolution, forKey: Keys.streamResolution)
        let mapped: String
        switch resolution {
        case "720p": mapped = "720p"
        case "1080p": mapped = "1080p"
        case "1080p HQ": mapped = "1080p-hq"
        default: mapped = "auto"
        }
        applyBetterXCloudPref("stream.video.resolution", value: mapped)
    }

    func applyServerRegion(_ region: String) {
        UserDefaults.standard.set(region, forKey: Keys.serverRegion)
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
        betterXCloudRefreshToken += 1
        if isStreaming, webURL.host?.contains("xbox.com") == true {
            pendingJavaScript = "try { location.reload(); } catch (e) {}"
        }
    }

    /// Clears network, catalog, artwork, and Better xCloud script caches without signing out.
    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        CloudCatalogService.clearDiskCache()
        ArtworkStore.shared.clear()
        BetterXCloudInjector.shared.invalidateCache()
        UserDefaults.standard.removeObject(forKey: "BetterXCloud.Script.v2")
        UserDefaults.standard.removeObject(forKey: "BetterXCloud.Script.Date.v2")
        betterXCloudRefreshToken += 1
        let store = WKWebsiteDataStore.default()
        var types = WKWebsiteDataStore.allWebsiteDataTypes()
        types.remove(WKWebsiteDataTypeCookies)
        types.remove(WKWebsiteDataTypeLocalStorage)
        types.remove(WKWebsiteDataTypeSessionStorage)
        types.remove(WKWebsiteDataTypeIndexedDBDatabases)
        types.remove(WKWebsiteDataTypeWebSQLDatabases)
        store.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                self?.reloadNonce += 1
                BetterXCloudInjector.shared.preload()
            }
        }
    }

    func clearWebData() {
        PlayActivityStore.shared.end()
        URLCache.shared.removeAllCachedResponses()
        CloudCatalogService.clearDiskCache()
        ArtworkStore.shared.clear()
        RemoteImageLoader.shared.clear()
        BetterXCloudInjector.shared.invalidateCache()
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                self?.clearLocalAuthFlag()
                self?.webURL = Self.idleWebURL
                self?.isStreaming = false
                self?.offerPlayNext = false
                self?.currentGame = nil
                self?.reloadNonce += 1
                HubState.shared.showNativeHub = true
                self?.requestedTab = .library
            }
        }
    }

    static var storedResolution: String { UserDefaults.standard.string(forKey: Keys.streamResolution) ?? "Auto" }
    static var storedRegion: String { UserDefaults.standard.string(forKey: Keys.serverRegion) ?? "Auto" }
}
