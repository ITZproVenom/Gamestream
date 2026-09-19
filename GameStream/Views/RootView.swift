import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var hub = HubState.shared
    @ObservedObject private var controller = ControllerManager.shared
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

    var body: some View {
        signedInRoot
    }

    private var signedInRoot: some View {
        // Background is full-bleed. Content respects the TOP safe area
        // (so the header is not under the status bar) and only extends under
        // the floating tab bar at the bottom — aurora fills the home-indicator
        // strip with no black borders.
        ZStack(alignment: .bottom) {
            Group {
                if session.isStreaming {
                    Color.black
                } else {
                    AnimatedBackground()
                }
            }
            .ignoresSafeArea()

            ZStack {
                if session.isStreaming && selectedTab == .library {
                    StreamPlayerView()
                        .zIndex(4)
                }

                if !session.isStreaming {
                    GameHubView()
                        .opacity(selectedTab == .library ? 1 : 0)
                        .allowsHitTesting(selectedTab == .library)
                        .accessibilityHidden(selectedTab != .library)
                        .zIndex(selectedTab == .library ? 2 : 0)

                    SearchHubView(isActive: selectedTab == .search)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            if session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               let game = session.continueGame {
                                ContinuePlayingCard(game: game)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                            }
                        }
                        .opacity(selectedTab == .search ? 1 : 0)
                        .allowsHitTesting(selectedTab == .search)
                        .accessibilityHidden(selectedTab != .search)
                        .zIndex(selectedTab == .search ? 2 : 0)

                    SettingsView(isActive: selectedTab == .settings)
                        .opacity(selectedTab == .settings ? 1 : 0)
                        .allowsHitTesting(selectedTab == .settings)
                        .accessibilityHidden(selectedTab != .settings)
                        .zIndex(selectedTab == .settings ? 2 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Only bottom — top safe area stays so the title is not clipped
            .ignoresSafeArea(edges: .bottom)

            if !hideTabBar {
                glassNavigation
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedTab) { _, tab in
            UserDefaults.standard.set(tab.rawValue, forKey: Self.tabStorageKey)
            if tab == .library && !session.isStreaming {
                session.returnToHub()
            }
        }
        .onChange(of: session.requestedTab) { _, tab in
            if let tab {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
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
                    withAnimation(.easeInOut(duration: 0.18)) {
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
            ControllerManager.shared.onPress = { press in
                handleControllerPress(press)
            }
            ControllerManager.shared.start()
            BetterXCloudInjector.shared.preload()
            syncIdleTimer()
            session.consumeLaunchResumeIfNeeded()
        }
    }

    // MARK: - Controller navigation

    private func handleControllerPress(_ press: ControllerManager.Press) {
        guard controller.isConnected, !session.isStreaming else { return }

        switch press {
        case .lb:
            advanceTab(-1)
        case .rb:
            advanceTab(1)
        case .left:
            advanceTab(-1)
        case .right:
            advanceTab(1)
        case .menu:
            HapticManager.impact()
            SoundManager.playTap()
            session.returnToHub()
        case .b:
            if selectedTab == .search || selectedTab == .settings {
                HapticManager.tap()
                SoundManager.playTap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    selectedTab = .library
                }
            }
        case .stickLeft:
            ControllerNavState.shared.send(.left)
        case .stickRight:
            ControllerNavState.shared.send(.right)
        case .stickUp:
            ControllerNavState.shared.send(.up)
        case .stickDown:
            ControllerNavState.shared.send(.down)
        case .a:
            ControllerNavState.shared.send(.activate)
        case .up, .down, .x, .y:
            break
        }
    }

    private func advanceTab(_ delta: Int) {
        let all = Tab.allCases
        guard let index = all.firstIndex(of: selectedTab) else { return }
        let next = all[(index + delta + all.count) % all.count]
        guard next != selectedTab else { return }
        HapticManager.tap()
        SoundManager.playTap()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selectedTab = next
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

    // MARK: - Liquid Glass tab switcher

    private var glassNavigation: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    navItem(tab)
                }
            }
            .padding(5)
            .background {
                // Base fill so content never bleeds through as sharp text
                // when glass compositing is delayed or reduced.
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .glassEffect(.regular, in: Capsule())
        }
    }

    private func navItem(_ tab: Tab) -> some View {
        Button {
            HapticManager.tap()
            SoundManager.playTap()
            if tab == .library && !session.isStreaming {
                session.returnToHub()
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
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
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .background {
            if selectedTab == tab {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .matchedGeometryEffect(id: "selectedTab", in: navNamespace)
                    .overlay {
                        if controller.isConnected {
                            Capsule()
                                .stroke(Color.accentColor, lineWidth: 2)
                                .padding(1.5)
                        }
                    }
            }
        }
    }
}
