import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @State private var selectedTab: Tab = .library

    enum Tab: String, CaseIterable {
        case library = "Library"
        case search = "Search"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .library: return "square.grid.2x2.fill"
            case .search: return "magnifyingglass"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                Group {
                    switch selectedTab {
                    case .library: LibraryView()
                    case .search: SearchView()
                    case .settings: SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AnimatedBackground())

            glassTabBar
        }
    }

    private var glassTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    SoundManager.playTap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.caption2)
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }
}
