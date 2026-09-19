import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var hub = HubState.shared
    @ObservedObject private var controller = ControllerManager.shared
    @State private var selectedTab: Tab = RootView.restoredTab()
    @State private var tabDragOffset: CGFloat = 0
    @State private var tabBarWidth: CGFloat = 0

    enum Tab: String, CaseIterable, Hashable {
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

        var index: Int {
            Tab.allCases.firstIndex(of: self) ?? 0
        }
    }

    private static let tabStorageKey = "GameStream.selectedTab"

    private var hideTabBar: Bool {
        session.isStreaming && selectedTab == .library
    }

    private var tabCount: CGFloat { CGFloat(Tab.allCases.count) }

    var body: some View {
        signedInRoot
    }

    private var signedInRoot: some View {
        ZStack(alignment: .bottom) {
            Group {
                if session.isStreaming {
                    Color.black
                } else {
                    AnimatedBackground()
                }
            }
            .ignoresSafeArea()

            Group {
                if session.isStreaming && selectedTab == .library {
                    StreamPlayerView()
                } else if !session.isStreaming {
                    // Page-style swipe between Library / Search / Settings
                    TabView(selection: $selectedTab) {
                        GameHubView()
                            .tag(Tab.library)

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
                            .tag(Tab.search)

                        SettingsView(isActive: selectedTab == .settings)
                            .tag(Tab.settings)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func selectTab(_ tab: Tab) {
        guard tab != selectedTab else { return }
        HapticManager.tap()
        SoundManager.playTap()
        if tab == .library && !session.isStreaming {
            session.returnToHub()
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selectedTab = tab
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

    // MARK: - Liquid Glass tab switcher (tap + slide on bar)

    private var glassNavigation: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let slot = width / tabCount
            let baseX = CGFloat(selectedTab.index) * slot
            let maxDragLeft = -baseX
            let maxDragRight = width - slot - baseX
            let clampedDrag = min(max(tabDragOffset, maxDragLeft), maxDragRight)
            let pillX = baseX + clampedDrag

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular, in: Capsule())

                Capsule()
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .overlay {
                        if controller.isConnected {
                            Capsule()
                                .stroke(Color.accentColor, lineWidth: 2)
                                .padding(1.5)
                        }
                    }
                    .frame(width: max(slot - 4, 0), height: 52)
                    .offset(x: pillX + 2)
                    .animation(
                        tabDragOffset == 0
                            ? .spring(response: 0.32, dampingFraction: 0.82)
                            : .interactiveSpring,
                        value: selectedTab
                    )

                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        tabLabel(tab)
                            .frame(width: slot, height: 52)
                            .contentShape(Rectangle())
                            .onTapGesture { selectTab(tab) }
                            .accessibilityLabel(tab.rawValue)
                            .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
            }
            .padding(5)
            .contentShape(Capsule())
            .gesture(tabDragGesture(slotWidth: slot))
            .onAppear { tabBarWidth = width }
            .onChange(of: width) { _, w in tabBarWidth = w }
        }
        .frame(height: 62)
    }

    private func tabLabel(_ tab: Tab) -> some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tabDragGesture(slotWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 0.6 else { return }
                tabDragOffset = value.translation.width
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                let delta = Int((predicted / max(slotWidth, 1)).rounded())
                let all = Tab.allCases
                let current = selectedTab.index
                let nextIndex = min(max(current + delta, 0), all.count - 1)
                tabDragOffset = 0
                if nextIndex != current {
                    selectTab(all[nextIndex])
                }
            }
    }
}
