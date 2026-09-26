import SwiftUI
import UIKit

/// Signed-in shell: full feature tabs. Streaming hands off to locked StreamPlayerView.
/// Layout targets iPhone 13 (390×844, notch) and scales via GeometryReader.
struct AppShell: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var hub = HubState.shared
    @State private var selectedTab: AppTab = AppShell.restoredTab()
    @State private var tabDragOffset: CGFloat = 0
    @State private var detailGame: CatalogGame?
    @State private var streamStartedAt: Date?

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
                    activeTab
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
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 4)
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
            DiagnosticsStore.shared.record(
                event: "navigation",
                feature: "tabs",
                properties: ["tab": tab.rawValue]
            )
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
                streamStartedAt = Date()
                let game = session.currentGame
                DiagnosticsStore.shared.record(
                    event: "streaming_started",
                    feature: "stream",
                    gameId: game?.id,
                    gameTitle: game?.title
                )
                if selectedTab != .home {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = .home
                    }
                }
            } else {
                hub.showNativeHub = true
                let duration: Double? = streamStartedAt.map { Date().timeIntervalSince($0) * 1000 }
                streamStartedAt = nil
                let game = session.currentGame
                DiagnosticsStore.shared.record(
                    event: "streaming_ended",
                    feature: "stream",
                    durationMs: duration,
                    gameId: game?.id,
                    gameTitle: game?.title
                )
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

    @ViewBuilder
    private var activeTab: some View {
        switch selectedTab {
        case .home:
            HomeFeature(onOpenGame: { detailGame = $0 })
        case .library:
            LibraryFeature(onOpenGame: { detailGame = $0 })
        case .search:
            SearchFeature(onOpenGame: { detailGame = $0 })
        case .settings:
            SettingsFeature()
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
