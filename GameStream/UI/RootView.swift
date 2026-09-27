import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: XboxAuth
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stream: StreamCoordinator

    @State private var tab: Tab = .home
    @State private var showingBrowser = false

    enum Tab: Hashable { case home, library, search, settings }

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                startupView
            case .signedOut:
                WelcomeView()
            case .signedIn:
                shell
            }
        }
        .tint(settings.accent.color)
        .preferredColorScheme(settings.theme.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: auth.state)
    }

    private var startupView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Checking your Xbox session…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var shell: some View {
        TabView(selection: $tab) {
            HomeView(showingBrowser: $showingBrowser)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            LibraryView()
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.library)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            SettingsView(showingBrowser: $showingBrowser)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        // The player covers everything, and dismissing it always ends the
        // session cleanly so Activity and the idle timer stay correct.
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
