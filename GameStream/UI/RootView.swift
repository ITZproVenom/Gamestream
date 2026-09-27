import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: XboxAuth
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var library: LibraryStore

    @State private var tab: MainTab = .home
    @State private var showingBrowser = false

    /// Named MainTab, not Tab: SwiftUI's own `Tab` view is used below, and a
    /// nested type with the same name shadows it.
    enum MainTab: Hashable { case home, library, search, stats, settings }

    var body: some View {
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
        TabView(selection: $tab) {
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
            get: { stream.phase.isActive },
            set: { presented in if !presented { stream.exit() } }
        )) {
            StreamView()
        }
        .sheet(isPresented: $showingBrowser) {
            BrowserView()
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
