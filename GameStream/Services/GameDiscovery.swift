import Foundation

enum DiscoveryMode: String, CaseIterable, Hashable {
    case multiplayer
    case coOp
    case solo
    case quickPlay
    case gamePass

    var title: String {
        switch self {
        case .multiplayer: return "Multiplayer"
        case .coOp: return "Co-op"
        case .solo: return "Solo"
        case .quickPlay: return "Quick play"
        case .gamePass: return "Game Pass"
        }
    }

    var subtitle: String {
        switch self {
        case .multiplayer: return "Jump in with other players"
        case .coOp: return "Play together on the couch or online"
        case .solo: return "Story and single-player sessions"
        case .quickPlay: return "Short sessions you can finish tonight"
        case .gamePass: return "Ready on Xbox Game Pass"
        }
    }

    var shelfTitle: String {
        switch self {
        case .multiplayer: return "Play with others"
        case .coOp: return "Co-op nights"
        case .solo: return "Solo stories"
        case .quickPlay: return "Quick play"
        case .gamePass: return "On Game Pass"
        }
    }
}

extension GameCatalog {
    static func modes(forId id: String) -> Set<DiscoveryMode> {
        switch id.uppercased() {
        case "9NNX1VVR3KNQ": return [.multiplayer, .gamePass]
        case "9NP1P1WFS0LB": return [.multiplayer, .coOp, .gamePass]
        case "BT5P2X999VH2": return [.multiplayer, .quickPlay]
        case "9NXP44L49SHJ": return [.multiplayer, .coOp, .gamePass]
        case "9P2N57MC619K": return [.multiplayer, .coOp, .gamePass]
        case "BQ1TN1T79V9K": return [.multiplayer, .quickPlay]
        case "9N201KQXS5BM": return [.multiplayer, .quickPlay]
        case "9NCJSXWZTP88": return [.solo, .gamePass]
        case "9PJTHRNVH62H": return [.coOp, .gamePass, .solo]
        case "9NKV34XDW014": return [.multiplayer, .coOp]
        case "9NBR2VXT87SJ": return [.solo, .gamePass]
        case "9NFTC552K3GJ": return [.solo, .quickPlay, .gamePass]
        case "9NX6K9HN4F4K": return [.solo, .gamePass]
        case "9N8CD0XZKLP4": return [.solo, .gamePass]
        case "9NB0115C9WNM": return [.coOp, .solo, .gamePass]
        default: return [.gamePass]
        }
    }

    static func modes(for game: CatalogGame) -> Set<DiscoveryMode> {
        modes(forId: game.id)
    }

    static func games(in mode: DiscoveryMode) -> [CatalogGame] {
        games.filter { modes(for: $0).contains(mode) }
    }

    static func discoveryShelves() -> [(String, [CatalogGame])] {
        DiscoveryMode.allCases.compactMap { mode in
            let items = games(in: mode)
            guard items.count >= 2 else { return nil }
            return (mode.shelfTitle, items)
        }
    }
}
