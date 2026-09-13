import SwiftUI
import UIKit

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
            // Keep Library (and its WKWebView) mounted so streams and cookies survive tab switches.
            LibraryView()
                .opacity(selectedTab == .library ? 1 : 0)
                .allowsHitTesting(selectedTab == .library)
                .zIndex(selectedTab == .library ? 1 : 0)

            if selectedTab == .search {
                SearchView()
                    .zIndex(2)
            } else if selectedTab == .settings {
                SettingsView()
                    .zIndex(2)
            }

            // Hide Liquid Glass tab bar while a game is streaming
            if !session.isStreaming {
                glassNavigation
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .zIndex(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AnimatedBackground())
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: session.isStreaming)
        .onChange(of: session.requestedTab) { _, newValue in
            if let tab = newValue {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    selectedTab = tab
                }
                session.requestedTab = nil
            }
        }
        .onChange(of: session.isStreaming) { _, streaming in
            UIApplication.shared.isIdleTimerDisabled = streaming
        }
        .onAppear {
            BetterXCloudInjector.shared.preload()
            UIApplication.shared.isIdleTimerDisabled = session.isStreaming
        }
    }

    private var glassNavigation: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    navItem(tab)
                }
            }
            .padding(5)
            .glassEffect(.regular, in: Capsule())
        }
    }

    private func navItem(_ tab: Tab) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            SoundManager.playTap()

            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if selectedTab == tab {
                Capsule()
                    .glassEffect(.regular.interactive())
                    .matchedGeometryEffect(id: "selectedTab", in: navNamespace)
            }
        }
    }
}
