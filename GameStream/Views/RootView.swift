import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @State private var selectedTab: Tab = .library
    @Namespace private var navNamespace

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
            // Content
            Group {
                switch selectedTab {
                case .library:
                    LibraryView()
                case .search:
                    SearchView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AnimatedBackground())

            // Floating Liquid Glass navigation
            glassNavigation
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .zIndex(10)
        }
    }

    private var glassNavigation: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    GlassNavigationItem(
                        title: tab.rawValue,
                        systemImage: tab.icon,
                        isSelected: selectedTab == tab,
                        namespace: navNamespace
                    ) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        SoundManager.playTap()

                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(6)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}
