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
        VStack(spacing: 0) {
            ZStack {
                if session.isStreaming && selectedTab == .library {
                    StreamPlayerView()
                        .zIndex(4)
                }

                GameHubView()
                    .ignoresSafeArea(
                        edges: (selectedTab == .library && !session.isStreaming)
                            ? [.bottom]
                            : []
                    )
                    .background {
                        if selectedTab == .library && !session.isStreaming {
                            AnimatedBackground()
                        }
                    }
                    .opacity(selectedTab == .library && !session.isStreaming ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library && !session.isStreaming)
                    .accessibilityHidden(selectedTab != .library || session.isStreaming)
                    .zIndex(selectedTab == .library && !session.isStreaming ? 2 : 0)

                SearchHubView(isActive: selectedTab == .search && !session.isStreaming)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           let game = session.continueGame {
                            ContinuePlayingCard(game: game)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                    }
                    .opacity(selectedTab == .search && !session.isStreaming ? 1 : 0)
                    .allowsHitTesting(selectedTab == .search && !session.isStreaming)
                    .accessibilityHidden(selectedTab != .search || session.isStreaming)
                    .zIndex(selectedTab == .search && !session.isStreaming ? 2 : 0)

                SettingsView(isActive: selectedTab == .settings && !session.isStreaming)
                    .opacity(selectedTab == .settings && !session.isStreaming ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings && !session.isStreaming)
                    .accessibilityHidden(selectedTab != .settings || session.isStreaming)
                    .zIndex(selectedTab == .settings && !session.isStreaming ? 2 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !hideTabBar {
                glassNavigation
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if session.isStreaming {
                Color.black.ignoresSafeArea()
            } else {
                AnimatedBackground()
            }
        }
        .onChange(of: selectedTab) { _, tab in
            UserDefaults.standard.set(tab.rawValue, forKey: Self.tabStorageKey)
            if tab == .library {
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
        // While streaming the game page owns the controller; never hijack it.
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
            // Back: a search/settings tab returns to the catalog.
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

    private var glassNavigation: some View {
        GlassEffectContainer(spacing: 8) {
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
            HapticManager.tap()
            SoundManager.playTap()
            if tab == .library {
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
                    .fill(.clear)
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
