import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: XboxAuth
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var library: LibraryStore

    @StateObject private var navigator = Navigator.shared
    @State private var showingBrowser = false
    /// Whether the player is on screen.
    ///
    /// Not read straight from the coordinator, because a game can be started
    /// from a sheet. A full-screen cover cannot be presented over a sheet
    /// that is already up: the request is dropped and the tap does nothing
    /// at all. The sheet is closed first and the player follows it.
    @State private var showingPlayer = false
    @State private var showingIntro = false

    /// Named MainTab, not Tab: SwiftUI's own `Tab` view is used below, and a
    /// nested type with the same name shadows it.
    enum MainTab: Hashable { case home, library, search, stats, settings }

    /// Where the app goes when something outside it asks — a Shortcut, a
    /// Spotlight result, a `gamestream://` link. Keeping one object means
    /// those routes cannot each grow their own half-working navigation.
    @MainActor
    final class Navigator: ObservableObject {
        static let shared = Navigator()
        @Published var tab: MainTab = .home
        @Published var presented: Game?
        @Published var searchSeed: String?
        private init() {}

        func show(_ game: Game) { presented = game }
        func showLibrary() { tab = .library }
        func search(_ text: String) {
            searchSeed = text
            tab = .search
        }
    }

    var body: some View {
        ZStack {
            Group {
                switch auth.state {
                case .unknown:
                    startup
                case .signedOut:
                    WelcomeView()
                case .signedIn:
                    shell
                }
            }
            .tint(settings.accent.color)
            .preferredColorScheme(settings.theme.colorScheme)
            .animation(.smooth(duration: 0.28), value: auth.state)

            // Over the top of everything, including the session check, so the
            // first thing on screen is the app rather than a spinner. It is
            // only ever shown once per cold launch.
            if showingIntro {
                IntroView(accent: settings.accent.color) {
                    withAnimation(.easeInOut(duration: 0.45)) { showingIntro = false }
                    IntroGate.shared.markPlayed()
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            showingIntro = settings.launchIntro && !IntroGate.shared.hasPlayed
        }
    }

    /// Whether the opening animation has already run in this process.
    ///
    /// Held outside the view because SwiftUI can rebuild the root view for
    /// reasons that have nothing to do with launching: the sign-in state
    /// settling is one, and replaying the intro every time it did would be
    /// the worst version of this feature.
    @MainActor
    final class IntroGate {
        static let shared = IntroGate()
        private(set) var hasPlayed = false
        private init() {}
        func markPlayed() { hasPlayed = true }
    }

    private var startup: some View {
        ZStack {
            AuroraBackground()
            GlassCard(padding: 24) {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Checking your Xbox session…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var shell: some View {
        TabView(selection: $navigator.tab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(showingBrowser: $showingBrowser)
            }

            Tab("Library", systemImage: "square.stack.fill", value: .library) {
                LibraryView()
            }

            Tab(value: .search, role: .search) {
                SearchView()
            }

            Tab("Insights", systemImage: "chart.bar.fill", value: .stats) {
                StatsView()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView(showingBrowser: $showingBrowser)
            }
        }
        // Liquid Glass: the tab bar shrinks out of the way while reading, and
        // the accessory above it keeps the last game one tap away.
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            ResumeAccessory()
        }
        // The player covers everything, and dismissing it always ends the
        // session cleanly so Insights and the idle timer stay correct.
        .fullScreenCover(isPresented: Binding(
            get: { showingPlayer },
            set: { presented in if !presented { stream.exit() } }
        )) {
            StreamView()
        }
        .onChange(of: stream.phase.isActive) { _, active in
            guard active else {
                showingPlayer = false
                return
            }
            let dismissingSheet = navigator.presented != nil || showingBrowser
            navigator.presented = nil
            showingBrowser = false
            guard dismissingSheet else {
                showingPlayer = true
                return
            }
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                showingPlayer = stream.phase.isActive
            }
        }
        .sheet(isPresented: $showingBrowser) {
            BrowserView()
        }
        .sheet(item: $navigator.presented) { game in
            NavigationStack {
                GameDetailView(game: game)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { navigator.presented = nil }
                        }
                    }
            }
        }
    }
}

/// The bottom accessory: resume the last game, or start what is queued.
///
/// This is the one control that is always reachable, so it never shows
/// anything the user cannot act on — with an empty library it stays away
/// rather than occupying the space with a placeholder.
struct ResumeAccessory: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var stream: StreamCoordinator

    var body: some View {
        if let game = target {
            Button {
                stream.play(game)
            } label: {
                HStack(spacing: 11) {
                    GameArtwork(url: game.posterURL, cornerRadius: 7)
                        .frame(width: 26, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isQueued ? "Up next" : "Continue")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(game.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(game.title)")
        }
    }

    private var isQueued: Bool { library.queue.first != nil }

    private var target: Game? {
        library.queue.first ?? library.recents.first
    }
}

/// Plain xbox.com, for anything the native interface does not cover.
///
/// This gets none of the player's scripts, which is why it scrolls and behaves
/// like the real site.
struct BrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0

    var body: some View {
        NavigationStack {
            XboxWebView(role: .browse, url: XboxAuth.playURL, reloadToken: reloadToken)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Xbox Cloud")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            reloadToken &+= 1
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Reload")
                    }
                }
        }
    }
}
