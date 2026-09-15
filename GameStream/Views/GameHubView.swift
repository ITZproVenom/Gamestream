import SwiftUI

enum HubBrowseFilter: Hashable {
    case all
    case forYou
    case favorites
    case recents
    case lists
    case activity
    case mode(DiscoveryMode)
    case genre(String)

    var title: String {
        switch self {
        case .all: return "All"
        case .forYou: return "For You"
        case .favorites: return "Favorites"
        case .recents: return "Recents"
        case .lists: return "Lists"
        case .activity: return "Activity"
        case .mode(let mode): return mode.title
        case .genre(let name): return name
        }
    }
}
