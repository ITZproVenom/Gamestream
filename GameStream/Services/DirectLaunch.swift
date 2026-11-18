import Foundation

/// A title the app can start, even when its own catalogue has never heard of it.
///
/// The catalogue the app reads is the Game Pass list, which lags and leaves
/// out anything that is not part of the subscription. A title that has just
/// been announced, or one that is free to play, can be in the cloud and
/// still missing from that list - and a title that is missing from the list
/// cannot be started from the app at all.
///
/// Given its product id, the app can ask for it directly. Whether the cloud
/// then streams it is the service's decision, not the app's: the session is
/// created on Microsoft's side, and if the title is not hosted there, no
/// claim the client makes will produce a picture.
enum DirectLaunch {

    /// A product id on its own, such as "9NNFG8BQRCXL".
    static func productID(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Xbox product ids are eleven characters of letters and digits,
        // and they are written in capitals.
        guard trimmed.count == 11 else { return nil }
        let allowed = CharacterSet.alphanumerics
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard trimmed.rangeOfCharacter(from: .letters) != nil,
              trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        return trimmed.uppercased()
    }

    /// The product id inside an Xbox link.
    ///
    /// The store and player links both end in the product id, with the slug
    /// before it: play.xbox.com/games/warzone/9NNFG8BQRCXL, or
    /// www.xbox.com/play/games/warzone/9NNFG8BQRCXL.
    static func productID(inLink text: String) -> (id: String, slug: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              host.contains("xbox.com") else { return nil }
        let parts = components.path
            .split(separator: "/")
            .map(String.init)
        guard parts.count >= 2 else { return nil }
        let last = parts[parts.count - 1]
        guard let id = productID(in: last) else { return nil }
        return (id, parts[parts.count - 2])
    }

    /// The title a product id refers to, as far as the app can tell.
    static func game(forID id: String, slug: String = "") -> Game {
        Game(id: id, slug: slug, title: id, tagline: "Opened by its product id")
    }
}
