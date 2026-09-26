import Foundation

struct TrackedGame: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var slug: String
    var title: String
    var lastSeen: Date
    var isFavorite: Bool

    var catalogURL: URL? {
        let slugPart = slug.isEmpty ? id.lowercased() : slug
        return URL(string: "https://www.xbox.com/play/games/\(slugPart)/\(id)")
    }

    var launchURL: URL? {
        let slugPart = slug.isEmpty ? id.lowercased() : slug
        return URL(string: "https://www.xbox.com/play/launch/\(slugPart)/\(id)")
    }
}

enum GameURLParser {
    /// Parses xbox.com/play/games/{slug}/{productId} and /play/launch/{slug}/{productId}.
    static func parse(_ raw: String) -> (slug: String, productId: String)? {
        guard let url = URL(string: raw), let host = url.host?.lowercased(), host == "xbox.com" || host.hasSuffix(".xbox.com") else {
            return nil
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let playIndex = parts.firstIndex(where: { $0.lowercased() == "play" }) else {
            return nil
        }
        let rest = Array(parts.dropFirst(playIndex + 1))
        guard rest.count >= 2 else { return nil }
        let kind = rest[0].lowercased()
        guard kind == "games" || kind == "launch" else { return nil }

        if rest.count >= 3 {
            let slug = sanitizeSlug(rest[1])
            let product = sanitizeProductId(rest[2])
            if !product.isEmpty { return (slug, product) }
        }

        let maybeId = sanitizeProductId(rest[1])
        if !maybeId.isEmpty { return (maybeId.lowercased(), maybeId) }
        return nil
    }

    static func displayTitle(fromPageTitle pageTitle: String?, slug: String, productId: String) -> String {
        if let pageTitle {
            var cleaned = pageTitle
            for suffix in [" | Xbox Cloud Gaming", " | Xbox", " - Xbox Cloud Gaming", " – Xbox"] {
                if let range = cleaned.range(of: suffix, options: .caseInsensitive) {
                    cleaned = String(cleaned[..<range.lowerBound])
                }
            }
            cleaned = cleaned.replacingOccurrences(of: "Play ", with: "", options: [.anchored, .caseInsensitive])
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count >= 2, cleaned.lowercased() != "xbox cloud gaming" {
                return cleaned
            }
        }
        if !slug.isEmpty {
            return slug
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return productId
    }

    private static func sanitizeSlug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
    }

    private static func sanitizeProductId(_ value: String) -> String {
        let trimmed = value.split(separator: "?").first.map(String.init) ?? value
        let allowed = CharacterSet.alphanumerics
        return trimmed.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
    }
}

struct GameCollection: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var gameIDs: [String]
    var createdAt: Date
}
