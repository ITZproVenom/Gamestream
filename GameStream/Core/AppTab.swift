import Foundation

/// Application tabs for the clean-slate shell.
/// Lives in Core so SessionStore can request tab changes without depending on Views.
enum AppTab: String, CaseIterable, Hashable {
    case home = "Home"
    case library = "Library"
    case search = "Search"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "books.vertical.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }

    var index: Int {
        AppTab.allCases.firstIndex(of: self) ?? 0
    }
}
