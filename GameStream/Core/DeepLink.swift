import Foundation
import CoreSpotlight

/// One place that turns an incoming URL or Spotlight result into an action.
///
/// Both routes end in the same request — "start this game" — so they resolve
/// through one function rather than two that drift apart.
@MainActor
enum DeepLink {
    enum Action: Equatable {
        case play(String)      // product ID or slug
        case open(String)      // show the game's page
        case search(String)
        case library
    }

    /// `gamestream://play/<id>`, `gamestream://game/<id>`,
    /// `gamestream://search/<text>`, `gamestream://library`
    static func action(for url: URL) -> Action? {
        guard url.scheme?.lowercased() == "gamestream" else { return nil }
        let host = (url.host ?? "").lowercased()
        let value = url.pathComponents.filter { $0 != "/" }.first ?? ""
        switch host {
        case "play" where !value.isEmpty: return .play(value)
        case "game" where !value.isEmpty: return .open(value)
        case "search": return .search(value.removingPercentEncoding ?? value)
        case "library": return .library
        default: return nil
        }
    }

    static func action(for activity: NSUserActivity) -> Action? {
        if activity.activityType == CSSearchableItemActionType,
           let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            return .open(id)
        }
        if let url = activity.webpageURL { return action(for: url) }
        return nil
    }

    /// Resolves an identifier the way a person would mean it: exact product
    /// ID first, then slug, then a title match.
    static func game(for identifier: String, in catalog: Catalog) -> Game? {
        let all = catalog.allGames
        if let exact = all.first(where: { $0.matches(id: identifier) }) { return exact }
        if let slug = all.first(where: { $0.slug.caseInsensitiveCompare(identifier) == .orderedSame }) {
            return slug
        }
        let needle = identifier.lowercased()
        return all.first { $0.title.lowercased() == needle }
            ?? all.first { $0.title.lowercased().contains(needle) }
    }
}
