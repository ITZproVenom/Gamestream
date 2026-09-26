import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var hub = HubState.shared
    @ObservedObject private var controller = ControllerManager.shared
    @State private var selectedTab: Tab = RootView.restoredTab()
    @State private var tabSliderProgress: CGFloat?
    @Namespace private var tabGlassNamespace

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
                } else {
                    // Keep only the active page in the hierarchy. This avoids the
                    // off-screen page stacking/gesture conflicts that can occur
                    // when several full-screen SwiftUI pages coexist in a TabView.
                    switch selectedTab {
                    case .library:
                        GameHubView()
                    case .search:
                        SearchHubView(isActive: true)
                            .safeAreaInset(edge: .top, spacing: 0) {
                                if session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                   let game = session.continueGame {
                                    ContinuePlayingCard(game: game)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)
                                }
                            }
                    case .settings:
                        SettingsView(isActive: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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

    // MARK: - Liquid Glass navigation slider

    private var glassNavigation: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let inset: CGFloat = 6
            let trackWidth = max(width - inset * 2, 1)
            let thumbWidth = max(min(trackWidth / tabCount, 116), 94)
            let usable = max(trackWidth - thumbWidth, 1)
            let selectedProgress = CGFloat(selectedTab.index) / max(tabCount - 1, 1)
            let progress = min(max(tabSliderProgress ?? selectedProgress, 0), 1)
            let thumbCenter = inset + thumbWidth / 2 + usable * progress
            let visibleIndex = min(
                max(Int((progress * CGFloat(Tab.allCases.count - 1)).rounded()), 0),
                Tab.allCases.count - 1
            )
            let visibleTab = Tab.allCases[visibleIndex]

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule())

                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        if tab != visibleTab {
                            sliderLabel(tab)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .allowsHitTesting(false)

                Capsule()
                    .fill(.clear)
                    .frame(width: thumbWidth, height: 52)
                    .glassEffect(
                        .regular
                            .tint(Color.accentColor.opacity(0.25))
                            .interactive(),
                        in: Capsule()
                    )
                    .glassEffectID("selected-tab", in: tabGlassNamespace)
                    .overlay {
                        sliderLabel(visibleTab)
                    }
                    .position(x: thumbCenter, y: 31)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: 62)
            .contentShape(Capsule())
            .gesture(tabSliderGesture(trackWidth: trackWidth, thumbWidth: thumbWidth))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Navigation")
            .accessibilityValue(visibleTab.rawValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    advanceTab(1)
                case .decrement:
                    advanceTab(-1)
                @unknown default:
                    break
                }
            }
        }
        .frame(height: 62)
    }

    private func sliderLabel(_ tab: Tab) -> some View {
        VStack(spacing: 3) {
            Image(systemName: tab.icon)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(tab.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(tab == selectedTab ? .primary : .secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func tabSliderGesture(trackWidth: CGFloat, thumbWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let usable = max(trackWidth - thumbWidth, 1)
                let thumbLeft = min(max(value.location.x - thumbWidth / 2, 0), usable)
                tabSliderProgress = thumbLeft / usable
            }
            .onEnded { value in
                let usable = max(trackWidth - thumbWidth, 1)
                let thumbLeft = min(max(value.location.x - thumbWidth / 2, 0), usable)
                let fraction = thumbLeft / usable
                let index = Int((fraction * CGFloat(Tab.allCases.count - 1)).rounded())
                tabSliderProgress = nil
                let next = Tab.allCases[min(max(index, 0), Tab.allCases.count - 1)]
                if next != selectedTab {
                    selectTab(next)
                }
            }
    }

}
