import Foundation

/// A game as shown anywhere in the app.
///
/// `Game` is deliberately self-contained: title, art, and launch identity all
/// travel together. 1.x stored only an ID in favourites and recents and looked
/// the rest up in the live catalog, so anything missing from today's Game Pass
/// response silently vanished from the user's own library. Keeping a full copy
/// means the library is readable offline and never loses entries.
struct Game: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var slug: String
    var title: String
    var tagline: String
    var genre: String
    var posterURL: URL?
    var heroURL: URL?

    init(id: String, slug: String = "", title: String, tagline: String = "",
         genre: String = "Cloud", posterURL: URL? = nil, heroURL: URL? = nil) {
        self.id = id
        self.slug = slug.isEmpty ? Game.slugify(title) : slug
        self.title = title
        self.tagline = tagline
        self.genre = genre
        self.posterURL = posterURL
        self.heroURL = heroURL
    }

    /// The page that starts the stream. Xbox redirects to the right locale.
    var launchURL: URL? {
        let safeSlug = slug.isEmpty ? id.lowercased() : slug
        return URL(string: "https://www.xbox.com/play/launch/\(safeSlug)/\(id)")
    }

    var storeURL: URL? {
        let safeSlug = slug.isEmpty ? id.lowercased() : slug
        return URL(string: "https://www.xbox.com/play/games/\(safeSlug)/\(id)")
    }

    static func slugify(_ value: String) -> String {
        var result = ""
        var pendingDash = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                pendingDash = false
            } else if !pendingDash && !result.isEmpty {
                result.append("-")
                pendingDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Product IDs are case-insensitive in Microsoft's catalog responses.
    func matches(id other: String) -> Bool {
        id.caseInsensitiveCompare(other) == .orderedSame
    }
}

/// One completed play session, used for the Activity screen.
struct PlayRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let gameID: String
    let title: String
    let startedAt: Date
    var seconds: TimeInterval

    init(id: UUID = UUID(), gameID: String, title: String,
         startedAt: Date, seconds: TimeInterval) {
        self.id = id
        self.gameID = gameID
        self.title = title
        self.startedAt = startedAt
        self.seconds = seconds
    }
}

/// A user-made collection of games.
struct GameList: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var gameIDs: [String]

    init(id: UUID = UUID(), name: String, gameIDs: [String] = []) {
        self.id = id
        self.name = name
        self.gameIDs = gameIDs
    }
}
