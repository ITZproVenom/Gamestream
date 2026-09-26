import SwiftUI
import UIKit

@MainActor
final class FreshPreferences: ObservableObject {
    static let shared = FreshPreferences()

    enum Theme: String, CaseIterable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    @Published var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "GameStream.fresh.theme") }
    }

    @Published var keepAwake: Bool {
        didSet { UserDefaults.standard.set(keepAwake, forKey: "GameStream.fresh.keepAwake") }
    }

    @Published var showActivity: Bool {
        didSet { UserDefaults.standard.set(showActivity, forKey: "GameStream.fresh.activity") }
    }

    @Published var accent: Int {
        didSet { UserDefaults.standard.set(accent, forKey: "GameStream.fresh.accent") }
    }

    private init() {
        theme = Theme(rawValue: UserDefaults.standard.string(forKey: "GameStream.fresh.theme") ?? "") ?? .system
        keepAwake = UserDefaults.standard.bool(forKey: "GameStream.fresh.keepAwake")
        showActivity = UserDefaults.standard.object(forKey: "GameStream.fresh.activity") as? Bool ?? true
        accent = UserDefaults.standard.object(forKey: "GameStream.fresh.accent") as? Int ?? 0
    }

    var tint: Color {
        switch accent {
        case 1: return .blue
        case 2: return .green
        case 3: return .orange
        case 4: return .pink
        default: return .purple
        }
    }

    var tintName: String {
        switch accent {
        case 1: return "Blue"
        case 2: return "Green"
        case 3: return "Orange"
        case 4: return "Pink"
        default: return "Purple"
        }
    }

    func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }
}

struct FreshAppRoot: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var catalog = FreshCatalogStore.shared
    @StateObject private var preferences = FreshPreferences.shared
    @State private var selectedTab: FreshTab = .home
    @State private var showingCloud = false
    @State private var showingSignIn = false

    var body: some View {
        Group {
            if session.isSignedIn {
                FreshMainShell(
                    selectedTab: $selectedTab,
                    showingCloud: $showingCloud
                )
            } else {
                FreshAuthLanding(showingSignIn: $showingSignIn)
            }
        }
        .environmentObject(catalog)
        .environmentObject(preferences)
        .preferredColorScheme(preferences.theme.colorScheme)
        .tint(preferences.tint)
        .onAppear {
            preferences.applyIdleTimer()
            session.revalidatePersistedLogin()
        }
        .onChange(of: preferences.keepAwake) { _, _ in
            preferences.applyIdleTimer()
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                selectedTab = .home
            }
        }
        .sheet(isPresented: $showingSignIn) {
            NavigationStack {
                SignInWebView()
                    .navigationTitle("Sign in")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingSignIn = false }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            .environmentObject(session)
        }
    }
}

enum FreshTab: Hashable {
    case home, library, search, settings
}

struct FreshMainShell: View {
    @EnvironmentObject private var session: SessionStore
    @Binding var selectedTab: FreshTab
    @Binding var showingCloud: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            FreshHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(FreshTab.home)

            FreshLibraryView()
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
                .tag(FreshTab.library)

            FreshSearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(FreshTab.search)

            FreshSettingsView(showingCloud: $showingCloud)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(FreshTab.settings)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { session.isStreaming },
                set: { presented in
                    if !presented && session.isStreaming {
                        session.exitStreamToHub()
                    }
                }
            )
        ) {
            StreamPlayerView()
                .environmentObject(session)
        }
        .sheet(isPresented: $showingCloud) {
            FreshCloudBrowser()
                .environmentObject(session)
        }
    }
}

struct FreshAuthLanding: View {
    @Binding var showingSignIn: Bool

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 30) {
                Spacer()

                Image(systemName: "cloud.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 10) {
                    Text("GameStream")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Xbox Cloud Gaming, without the clutter.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("Sign in with Microsoft to access your cloud games. The sign-in page is hosted by Microsoft.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showingSignIn = true
                } label: {
                    HStack {
                        Text("Continue with Microsoft")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Your Microsoft password is entered only on Microsoft's hosted page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
        }
    }
}

struct FreshHomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var catalog: FreshCatalogStore
    @EnvironmentObject private var preferences: FreshPreferences
    @State private var selectedGame: FreshGame?
    @State private var showingLists = false
    @State private var showingActivity = false

    private var recentGames: [FreshGame] {
        session.recents.compactMap { tracked in
            catalog.games.first { $0.id.caseInsensitiveCompare(tracked.id) == .orderedSame }
        }
    }

    private var favoriteGames: [FreshGame] {
        session.favorites.compactMap { tracked in
            catalog.games.first { $0.id.caseInsensitiveCompare(tracked.id) == .orderedSame }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    FreshPageHeader(
                        title: greetingTitle,
                        subtitle: "Xbox Cloud Gaming",
                        trailing: {
                            Button {
                                session.openXboxCloud()
                            } label: {
                                Image(systemName: "cloud.fill")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Open Xbox Cloud Gaming")
                        }
                    )

                    if catalog.isLoading && catalog.games.isEmpty {
                        FreshLoadingBlock()
                    } else if let error = catalog.errorMessage, catalog.games.isEmpty {
                        FreshErrorBlock(message: error) {
                            catalog.refresh()
                        }
                    } else {
                        if let hero = catalog.featured.first {
                            FreshHero(game: hero) {
                                selectedGame = hero
                            } play: {
                                session.play(hero.tracked)
                            }
                        }

                        if !recentGames.isEmpty {
                            FreshSectionHeader(
                                title: "Continue playing",
                                actionTitle: "See all"
                            ) {
                                showingActivity = true
                            }

                            FreshHorizontalGames(games: Array(recentGames.prefix(8))) {
                                selectedGame = $0
                            }
                        }

                        if !favoriteGames.isEmpty {
                            FreshSectionHeader(title: "Favorites")
                            FreshHorizontalGames(games: Array(favoriteGames.prefix(8))) {
                                selectedGame = $0
                            }
                        }

                        if preferences.showActivity, !session.playRecords.isEmpty {
                            FreshActivitySummary(records: session.playRecords) {
                                showingActivity = true
                            }
                        }

                        FreshSectionHeader(title: "Browse")
                        FreshBrowseTiles(
                            genres: Array(catalog.genres.prefix(6)),
                            games: catalog.games
                        ) { game in
                            selectedGame = game
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationDestination(item: $selectedGame) { game in
                FreshGameDetail(game: game)
            }
            .sheet(isPresented: $showingLists) {
                FreshListsView()
            }
            .sheet(isPresented: $showingActivity) {
                FreshActivityView()
            }
            .refreshable {
                catalog.refresh()
            }
        }
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }
}

struct FreshLibraryView: View {
    enum Filter: Hashable {
        case all, favorites, recent, genre(String)

        var title: String {
            switch self {
            case .all: return "All games"
            case .favorites: return "Favorites"
            case .recent: return "Recently played"
            case .genre(let name): return name
            }
        }
    }

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var catalog: FreshCatalogStore
    @State private var filter: Filter = .all
    @State private var selectedGame: FreshGame?
    @State private var showingLists = false

    private var games: [FreshGame] {
        switch filter {
        case .all:
            return catalog.games
        case .favorites:
            return session.favorites.compactMap { tracked in
                catalog.games.first { $0.id.caseInsensitiveCompare(tracked.id) == .orderedSame }
            }
        case .recent:
            return session.recents.compactMap { tracked in
                catalog.games.first { $0.id.caseInsensitiveCompare(tracked.id) == .orderedSame }
            }
        case .genre(let name):
            return catalog.genreGames(name)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if catalog.isLoading && catalog.games.isEmpty {
                    FreshLoadingBlock()
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)
                            ],
                            spacing: 18
                        ) {
                            ForEach(games) { game in
                                FreshPosterTile(game: game) {
                                    selectedGame = game
                                } play: {
                                    session.play(game.tracked)
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(filter.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All games") { filter = .all }
                        Button("Favorites") { filter = .favorites }
                        Button("Recently played") { filter = .recent }
                        if !catalog.genres.isEmpty {
                            Divider()
                            ForEach(catalog.genres.prefix(12), id: \.self) { genre in
                                Button(genre) { filter = .genre(genre) }
                            }
                        }
                        Divider()
                        Button("Manage lists") { showingLists = true }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Library filters")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        catalog.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh catalog")
                }
            }
            .navigationDestination(item: $selectedGame) { game in
                FreshGameDetail(game: game)
            }
            .sheet(isPresented: $showingLists) {
                FreshListsView()
            }
        }
    }
}

struct FreshSearchView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var catalog: FreshCatalogStore
    @State private var query = ""
    @State private var selectedGame: FreshGame?

    private var results: [FreshGame] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        return catalog.search(trimmed)
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    FreshSearchStart(games: catalog.games, recentSearches: recentSearches) {
                        query = $0
                    }
                } else {
                    ScrollView {
                        if results.isEmpty {
                            ContentUnavailableView(
                                "No games found",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different title or genre.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)
                                ],
                                spacing: 18
                            ) {
                                ForEach(results) { game in
                                    FreshPosterTile(game: game) {
                                        selectedGame = game
                                    } play: {
                                        session.play(game.tracked)
                                    }
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Games, genres, features")
            .onSubmit(of: .search) {
                remember(query)
            }
            .navigationDestination(item: $selectedGame) { game in
                FreshGameDetail(game: game)
            }
        }
    }

    private var recentSearches: [String] {
        UserDefaults.standard.stringArray(forKey: "GameStream.fresh.searches") ?? []
    }

    private func remember(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var values = recentSearches.filter { $0.caseInsensitiveCompare(clean) != .orderedSame }
        values.insert(clean, at: 0)
        UserDefaults.standard.set(Array(values.prefix(8)), forKey: "GameStream.fresh.searches")
    }
}

struct FreshSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var preferences: FreshPreferences
    @EnvironmentObject private var catalog: FreshCatalogStore
    @Binding var showingCloud: Bool

    @State private var resolution = "Auto"
    @State private var region = "Auto"
    @State private var confirmClear = false
    @State private var showAbout = false

    private let resolutions = ["Auto", "720p", "1080p", "1080p HQ"]
    private let regions = ["Auto", "North America", "Europe", "Asia", "Australia"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(FreshPreferences.Theme.allCases, id: \.self) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }

                    Picker("Accent", selection: $preferences.accent) {
                        Text("Purple").tag(0)
                        Text("Blue").tag(1)
                        Text("Green").tag(2)
                        Text("Orange").tag(3)
                        Text("Pink").tag(4)
                    }

                    Toggle("Keep screen awake", isOn: $preferences.keepAwake)
                    Toggle("Show activity on Home", isOn: $preferences.showActivity)
                }

                Section("Streaming") {
                    Picker("Quality", selection: $resolution) {
                        ForEach(resolutions, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .onChange(of: resolution) { _, value in
                        session.applyStreamResolution(value)
                    }

                    Picker("Server region", selection: $region) {
                        ForEach(regions, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .onChange(of: region) { _, value in
                        session.applyServerRegion(value)
                    }

                    Button {
                        session.refreshBetterXCloudScript()
                    } label: {
                        Label("Refresh Better xCloud", systemImage: "arrow.clockwise")
                    }

                    Button {
                        showingCloud = true
                    } label: {
                        Label("Open Xbox Cloud Gaming", systemImage: "cloud.fill")
                    }
                }

                Section("Controller") {
                    Toggle(
                        "Controller haptics",
                        isOn: Binding(
                            get: {
                                UserDefaults.standard.object(forKey: "GameStream.controllerHapticsEnabled") as? Bool ?? true
                            },
                            set: {
                                UserDefaults.standard.set($0, forKey: "GameStream.controllerHapticsEnabled")
                            }
                        )
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Rumble intensity")
                            Spacer()
                            Text(String(format: "%.1fx", rumbleIntensity))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: Binding(
                                get: { rumbleIntensity },
                                set: {
                                    rumbleIntensity = $0
                                    UserDefaults.standard.set($0, forKey: "GameStream.controllerRumbleIntensity")
                                }
                            ),
                            in: 0.5...3.0
                        )

                        Button("Test haptics") {
                            ControllerRumble.shared.playTest()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Library") {
                    LabeledContent("Games", value: "\(catalog.games.count)")
                    LabeledContent("Favorites", value: "\(session.favorites.count)")
                    LabeledContent("Recently played", value: "\(session.recents.count)")
                    LabeledContent("Up next", value: "\(session.queue.count)")
                    Button("Clear favorites", role: .destructive) {
                        session.clearFavorites()
                    }
                    Button("Clear recently played", role: .destructive) {
                        session.clearRecents()
                    }
                }

                Section("Account") {
                    LabeledContent("Account", value: session.accountLabel ?? "Xbox Account")
                    Button("Sign out", role: .destructive) {
                        session.signOut()
                    }
                }

                Section {
                    Button("About GameStream") {
                        showAbout = true
                    }

                    Button("Refresh catalog") {
                        catalog.refresh()
                    }

                    Button("Clear local cache", role: .destructive) {
                        confirmClear = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                resolution = session.storedResolution
                region = session.storedRegion
                if resolution.isEmpty { resolution = "Auto" }
                if region.isEmpty { region = "Auto" }
            }
            .confirmationDialog(
                "Clear local cache?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                Button("Clear cache", role: .destructive) {
                    catalog.games = []
                    catalog.refresh()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the fresh catalog from memory and reloads it from Xbox.")
            }
            .sheet(isPresented: $showAbout) {
                FreshAboutView()
            }
        }
    }

    private var rumbleIntensity: Double {
        let value = UserDefaults.standard.object(forKey: "GameStream.controllerRumbleIntensity") as? Double
        return min(max(value ?? 1.6, 0.5), 3.0)
    }
}

struct FreshGameDetail: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var catalog: FreshCatalogStore
    @Environment(.dismiss) private var dismiss
    let game: FreshGame
    @State private var showingLists = false

    private var isFavorite: Bool { session.isFavorite(game.id) }
    private var isQueued: Bool { session.isQueued(game.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FreshHeroImage(url: game.posterURL)
                    .aspectRatio(16 / 9, contentMode: .fit)

                VStack(alignment: .leading, spacing: 9) {
                    Text(game.title)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        FreshPill(text: game.genre)
                        FreshPill(text: "Xbox Cloud")
                    }

                    if !game.tagline.isEmpty {
                        Text(game.tagline)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        session.play(game.tracked)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        session.toggleFavorite(game.tracked)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
                }

                Button {
                    session.toggleQueue(game.tracked)
                } label: {
                    Label(
                        isQueued ? "Remove from Up Next" : "Add to Up Next",
                        systemImage: isQueued ? "text.badge.minus" : "text.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                FreshInfoRow(title: "Genre", value: game.genre)
                FreshInfoRow(title: "Provider", value: "Xbox Cloud Gaming")

                if !catalog.genres.isEmpty {
                    FreshSectionHeader(title: "More like this")
                    FreshHorizontalGames(
                        games: Array(catalog.genreGames(game.genre).filter { $0.id != game.id }.prefix(8))
                    ) {
                        // Detail navigation is handled by the parent stack.
                    }
                }

                Button {
                    showingLists = true
                } label: {
                    Label("Add to a list", systemImage: "text.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLists) {
            FreshListsPicker(game: game)
        }
    }
}

struct FreshHero: View {
    let game: FreshGame
    let open: () -> Void
    let play: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FreshHeroImage(url: game.posterURL)
                .frame(height: 310)
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0), location: 0.30),
                            .init(color: .black.opacity(0.70), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: 11) {
                Text("FEATURED")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.8))

                Text(game.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Button(action: play) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)

                    Button(action: open) {
                        Text("Details")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
    }
}

struct FreshHorizontalGames: View {
    let games: [FreshGame]
    let action: (FreshGame) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(games) { game in
                    FreshMiniCard(game: game) {
                        action(game)
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in
                        min(max(width * 0.37, 128), 170)
                    }
                }
            }
        }
    }
}

struct FreshMiniCard: View {
    let game: FreshGame
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                FreshHeroImage(url: game.posterURL)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(game.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FreshPosterTile: View {
    let game: FreshGame
    let open: () -> Void
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                FreshHeroImage(url: game.posterURL)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.white)
                            .padding(9)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)

            Text(game.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            HStack {
                Text(game.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct FreshHeroImage: View {
    let url: URL?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(uiColor: .tertiarySystemFill))

            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .clipped()
    }

    private var fallback: some View {
        Image(systemName: "gamecontroller.fill")
            .font(.system(size: 42))
            .foregroundStyle(.tertiary)
    }
}

struct FreshSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.bold))

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

struct FreshPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: () -> Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            trailing()
        }
    }
}

struct FreshBrowseTiles: View {
    let genres: [String]
    let games: [FreshGame]
    let action: (FreshGame) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(Array(genres.enumerated()), id: \.offset) { _, genre in
                let game = games.first { $0.genre == genre }
                Button {
                    if let game { action(game) }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(genre)
                            .font(.headline)
                        Text("\(games.filter { $0.genre == genre }.count) games")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FreshSearchStart: View {
    let games: [FreshGame]
    let recentSearches: [String]
    let select: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        FreshSectionHeader(title: "Recent searches")
                        ForEach(recentSearches, id: \.self) { value in
                            Button {
                                select(value)
                            } label: {
                                Label(value, systemImage: "clock")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                FreshSectionHeader(title: "Browse by genre")
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(Array(Set(games.map(\\.genre)).sorted().prefix(12)), id: \.self) { genre in
                        Button {
                            select(genre)
                        } label: {
                            Text(genre)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
    }
}

struct FreshActivitySummary: View {
    let records: [PlayRecord]
    let open: () -> Void

    private var total: TimeInterval {
        records.prefix(100).reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your activity")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                Text("You've played for \(format(total)) across \(records.count) recent sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

struct FreshActivityView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var catalog: FreshCatalogStore

    var body: some View {
        NavigationStack {
            List {
                if session.playRecords.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "clock",
                        description: Text("Play a cloud game for a few seconds and your sessions will appear here.")
                    )
                } else {
                    ForEach(session.playRecords.prefix(100)) { record in
                        HStack(spacing: 14) {
                            let game = catalog.games.first { $0.id.caseInsensitiveCompare(record.gameID) == .orderedSame }
                            FreshHeroImage(url: game?.posterURL)
                                .frame(width: 48, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(format(record.seconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

struct FreshListsView: View {
    @EnvironmentObject private var lists: FreshListsStore
    @EnvironmentObject private var catalog: FreshCatalogStore
    @Environment(.dismiss) private var dismiss
    @State private var showingCreate = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if lists.lists.isEmpty {
                    ContentUnavailableView(
                        "No lists yet",
                        systemImage: "text.badge.plus",
                        description: Text("Create a list to organize games for later.")
                    )
                } else {
                    ForEach(lists.lists) { list in
                        NavigationLink {
                            FreshListDetail(list: list)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name)
                                    .font(.headline)
                                Text("\(list.gameIDs.count) games")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            lists.delete(lists.lists[index])
                        }
                    }
                }
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newName = ""
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New list", isPresented: $showingCreate) {
                TextField("List name", text: $newName)
                Button("Create") {
                    lists.create(name: newName)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .environmentObject(lists)
        .environmentObject(catalog)
    }
}

struct FreshListDetail: View {
    @EnvironmentObject private var lists: FreshListsStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var catalog: FreshCatalogStore
    let list: FreshList

    private var currentList: FreshList {
        lists.lists.first { $0.id == list.id } ?? list
    }

    private var games: [FreshGame] {
        currentList.gameIDs.compactMap { id in
            catalog.games.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
        }
    }

    var body: some View {
        List {
            if games.isEmpty {
                ContentUnavailableView(
                    "List is empty",
                    systemImage: "square.stack",
                    description: Text("Add games from a game's detail page.")
                )
            } else {
                ForEach(games) { game in
                    HStack(spacing: 12) {
                        FreshHeroImage(url: game.posterURL)
                            .frame(width: 44, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(game.title).font(.subheadline.weight(.semibold))
                            Text(game.genre).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            session.play(game.tracked)
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            lists.toggle(game: game.id, in: currentList)
                        } label: {
                            Label("Remove", systemImage: "minus")
                        }
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FreshListsPicker: View {
    @EnvironmentObject private var lists: FreshListsStore
    @Environment(.dismiss) private var dismiss
    let game: FreshGame

    var body: some View {
        NavigationStack {
            List {
                if lists.lists.isEmpty {
                    ContentUnavailableView(
                        "No lists",
                        systemImage: "text.badge.plus",
                        description: Text("Create a list in Library first.")
                    )
                } else {
                    ForEach(lists.lists) { list in
                        Button {
                            lists.toggle(game: game.id, in: list)
                        } label: {
                            HStack {
                                Text(list.name)
                                Spacer()
                                if lists.contains(game: game.id, in: list) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct FreshAboutView: View {
    @Environment(.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text("GameStream")
                    .font(.title.weight(.bold))

                Text("A native Xbox Cloud Gaming companion focused on a clean library, fast discovery and a quiet interface.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Text("iOS • 26+")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct FreshInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct FreshPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(Capsule())
    }
}

struct FreshLoadingBlock: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading the Xbox catalog…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }
}

struct FreshErrorBlock: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
            Text("Catalog unavailable")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct FreshCloudBrowser: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            XboxCloudWebView(url: $session.webURL)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationTitle("Xbox Cloud")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
