import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var hub = HubState.shared
    @ObservedObject private var controller = ControllerManager.shared
    @State private var selectedTab: Tab = RootView.restoredTab()

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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                PlayActivityStore.shared.resume()
            case .inactive, .background:
                PlayActivityStore.shared.pause()
            @unknown default:
                break
            }
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
        .onDisappear {
            ControllerManager.shared.onPress = nil
            UIApplication.shared.isIdleTimerDisabled = false
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
            if selectedTab == .library {
                ControllerNavState.shared.send(.left)
            }
        case .right:
            if selectedTab == .library {
                ControllerNavState.shared.send(.right)
            }
        case .up:
            if selectedTab == .library {
                ControllerNavState.shared.send(.up)
            }
        case .down:
            if selectedTab == .library {
                ControllerNavState.shared.send(.down)
            }
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
        case .x, .y:
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

    // MARK: - Bottom navigation

    private var glassNavigation: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectTab(tab)
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                        .background {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.14))
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .frame(maxWidth: 430)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 7)
    }

}
