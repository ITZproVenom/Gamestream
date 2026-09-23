import SwiftUI
import UIKit

/// Signed-in shell: full feature tabs. Streaming hands off to locked StreamPlayerView.
struct AppShell: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var hub = HubState.shared
    @State private var selectedTab: AppTab = AppShell.restoredTab()
    @State private var tabDragOffset: CGFloat = 0
    @State private var detailGame: CatalogGame?

    private static let tabStorageKey = "GameStream.appSelectedTab"

    private var hideTabBar: Bool {
        session.isStreaming && selectedTab == .home
    }

    var body: some View {
        ZStack {
            Group {
                if session.isStreaming {
                    Color.black
                } else {
                    AppBackground()
                }
            }
            .ignoresSafeArea()

            Group {
                if session.isStreaming && selectedTab == .home {
                    StreamPlayerView()
                        .ignoresSafeArea()
                } else if !session.isStreaming {
                    TabView(selection: $selectedTab) {
                        HomeFeature(onOpenGame: { detailGame = $0 })
                            .tag(AppTab.home)
                        LibraryFeature(onOpenGame: { detailGame = $0 })
                            .tag(AppTab.library)
                        SearchFeature(onOpenGame: { detailGame = $0 })
                            .tag(AppTab.search)
                        SettingsFeature()
                            .tag(AppTab.settings)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hideTabBar {
                GlassTabBar(
                    selected: $selectedTab,
                    dragOffset: $tabDragOffset
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
        }
        .sheet(item: $detailGame) { game in
            NavigationStack {
                GameDetailsFeature(game: game)
            }
            .environmentObject(session)
            .presentationDetents([.large])
        }
        .onChange(of: selectedTab) { _, tab in
            UserDefaults.standard.set(tab.rawValue, forKey: Self.tabStorageKey)
            if tab == .home && !session.isStreaming {
                session.returnToHub()
                session.refreshXboxPlayHistory()
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
            UIApplication.shared.isIdleTimerDisabled = streaming || session.keepScreenAwake
            if streaming {
                hub.showNativeHub = false
                if selectedTab != .home {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = .home
                    }
                }
            } else {
                hub.showNativeHub = true
                session.refreshXboxPlayHistory(force: true)
            }
        }
        .onAppear {
            BetterXCloudInjector.shared.preload()
            UIApplication.shared.isIdleTimerDisabled = session.isStreaming || session.keepScreenAwake
            session.consumeLaunchResumeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                session.refreshXboxPlayHistory()
            }
        }
    }

    private static func restoredTab() -> AppTab {
        if let raw = UserDefaults.standard.string(forKey: tabStorageKey),
           let tab = AppTab(rawValue: raw) {
            return tab
        }
        return .home
    }
}
