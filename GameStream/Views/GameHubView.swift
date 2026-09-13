import SwiftUI

enum HubBrowseFilter: Hashable {
    case all
    case favorites
    case recents
    case lists
    case genre(String)

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .recents: return "Recents"
        case .lists: return "Lists"
        case .genre(let name): return name
        }
    }
}
