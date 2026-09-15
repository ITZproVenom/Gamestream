import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var hub = HubState.shared
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

    private var hideTabBar: Bool {
        session.isStreaming && selectedTab == .library
    }

    /// Native GameHub is the Library tab. WebView exists only while streaming.
    private var showingHub: Bool {
        selectedTab == .library && !session.isStreaming
    }

    var body: some View {
        signedInRoot
    }

    private var signedInRoot: some View {
        ZStack(alignment: .bottom) {
            if session.isStreaming && selectedTab == .library {
                LibraryView()
                    .zIndex(1)
            }

            if showingHub {
                GameHubView()
                    .zIndex(3)
            }

            if selectedTab == .search {
                SearchHubView()
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AnimatedBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hideTabBar {
                glassNavigation
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hideTabBar)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: showingHub)
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
            if streaming {
                hub.showNativeHub = false
                if selectedTab != .library {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selectedTab = .library
                    }
                }
            } else {
                hub.showNativeHub = true
            }
        }
        .onChange(of: session.keepScreenAwake) { _, _ in
            syncIdleTimer()
        }
        .onAppear {
            BetterXCloudInjector.shared.preload()
            syncIdleTimer()
            session.consumeLaunchResumeIfNeeded()
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
            if tab == .library {
                session.returnToHub()
            }
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
