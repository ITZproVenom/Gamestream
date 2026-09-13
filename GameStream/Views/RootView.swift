import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @State private var selectedTab: Tab = RootView.restoredTab()
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

    private static let tabStorageKey = "GameStream.selectedTab"

    /// Hide the tab bar only when the stream is actually on screen.
    private var hideTabBar: Bool {
        session.isStreaming && selectedTab == .library
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
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           let game = session.continueGame {
                            ContinuePlayingCard(game: game)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                    }
                    .zIndex(2)
            } else if selectedTab == .settings {
                SettingsView()
                    .zIndex(2)
            }

            if !hideTabBar {
                glassNavigation
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .zIndex(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AnimatedBackground())
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hideTabBar)
        .onChange(of: selectedTab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.tabStorageKey)
        }
        .onChange(of: session.requestedTab) { _, newValue in
            if let tab = newValue {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    selectedTab = tab
                }
                session.requestedTab = nil
            }
        }
        .onChange(of: session.isStreaming) { _, streaming in
            syncIdleTimer()
            // Never leave the user on Search/Settings with no tab bar while a game is running.
            if streaming && selectedTab != .library {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    selectedTab = .library
                }
            }
        }
        .onChange(of: session.keepScreenAwake) { _, _ in
            syncIdleTimer()
        }
        .onAppear {
            BetterXCloudInjector.shared.preload()
            syncIdleTimer()
        }
    }

    private func syncIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = session.isStreaming || session.keepScreenAwake
    }

    private static func restoredTab() -> Tab {
        if let raw = UserDefaults.standard.string(forKey: tabStorageKey),
           let tab = Tab(rawValue: raw) {
            return tab
        }
        return .library
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .background {
            if selectedTab == tab {
                Capsule()
                    .glassEffect(.regular.interactive())
                    .matchedGeometryEffect(id: "selectedTab", in: navNamespace)
            }
        }
    }
}
