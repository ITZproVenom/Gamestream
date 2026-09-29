import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var auth: XboxAuth

    @Binding var showingBrowser: Bool

    @State private var showingActivity = false
    @State private var genre: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if let error = catalog.errorMessage, catalog.games.isEmpty {
                        ErrorNotice(title: "Catalog unavailable", message: error) {
                            Task { await catalog.refresh() }
                        }
                        .padding(.horizontal, Theme.pageInset)
                    } else if catalog.games.isEmpty && catalog.isLoading {
                        LoadingNotice()
                    }

                    if !catalog.featured.isEmpty {
                        heroCarousel
                    }

                    quickActions

                    if !library.recents.isEmpty {
                        section("Jump back in", subtitle: "Where you left off") {
                            GameShelf(games: Array(library.recents.prefix(12))) { game in
                                let played = library.playtime(forGameID: game.id)
                                return played > 0 ? Format.duration(played) : nil
                            }
                        }
                    }

                    if !library.queue.isEmpty {
                        section("Up next", subtitle: "\(library.queue.count) queued") {
                            GameShelf(games: library.queue)
                        }
                    }

                    if !library.favorites.isEmpty {
                        section("Favorites") {
                            GameShelf(games: Array(library.favorites.prefix(14)))
                        }
                    }

                    if !catalog.genres.isEmpty {
                        genreBrowser
                    }

                    if !catalog.games.isEmpty {
                        section(genre.map { "More in \($0)" } ?? "In the cloud",
                                subtitle: "\(catalog.games.count) games ready to stream") {
                            GameShelf(games: popular, width: 138)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 36)
                // The page is exactly as wide as the screen, whatever a
                // child would prefer. Without this one greedy row drags
                // every other row off the right edge with it.
                .containerRelativeFrame(.horizontal)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AuroraBackground() }
            .refreshable { await catalog.refresh() }
            .navigationTitle(greeting)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        surpriseMe()
                    } label: {
                        Image(systemName: "dice.fill")
                    }
                    .accessibilityLabel("Play something random")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingBrowser = true
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open xbox.com")
                }
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .sheet(isPresented: $showingActivity) { ActivityView() }
        }
    }

    // MARK: - Hero

    private var heroCarousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(catalog.featured) { game in
                    HeroCard(game: game) { stream.play(game) }
                        .containerRelativeFrame(.horizontal, count: 1, spacing: 14)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.55)
                                .scaleEffect(phase.isIdentity ? 1 : 0.93)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        // The inset belongs to the scroll view, not to the row inside it.
        //
        // containerRelativeFrame measures the scroll container, so padding
        // the row gave every card the full width of the screen and then
        // pushed it in by twenty points: the card ran off the right edge by
        // exactly the padding, and the page looked shifted. As a safe area
        // inset the container is measured after the inset, so the card is
        // the width it is supposed to be.
        .safeAreaPadding(.horizontal, Theme.pageInset)
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            StatChip(value: Format.duration(library.playtimeToday),
                     caption: "Played today",
                     systemImage: "clock.fill")

            StatChip(value: "\(library.streakDays)",
                     caption: "Day streak",
                     systemImage: "flame.fill")

            Button {
                showingActivity = true
            } label: {
                StatChip(value: "\(library.activity.count)",
                         caption: "Sessions logged",
                         systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.pageInset)
    }

    // MARK: - Genres

    private var genreBrowser: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: "Browse", subtitle: "Filter the shelf below")
                .padding(.horizontal, Theme.pageInset)

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    FilterChip(title: "All", isSelected: genre == nil) {
                        withAnimation(.smooth) { genre = nil }
                    }
                    ForEach(catalog.genres, id: \.self) { name in
                        FilterChip(title: name, isSelected: genre == name) {
                            withAnimation(.smooth) { genre = (genre == name) ? nil : name }
                        }
                    }
                }
                .padding(.horizontal, Theme.pageInset)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var popular: [Game] {
        let base = genre.map { catalog.games(inGenre: $0) } ?? catalog.games
        return Array(base.prefix(24))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, subtitle: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, Theme.pageInset)
            content()
        }
    }

    private func surpriseMe() {
        guard let pick = catalog.randomGame() else { return }
        AppLog.shared.info("home", "random pick: \(pick.title)")
        stream.play(pick)
    }

    private var greeting: String {
        let name = auth.state.gamertag
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<12: return name.map { "Morning, \($0)" } ?? "Good morning"
        case ..<18: return name.map { "Afternoon, \($0)" } ?? "Good afternoon"
        default: return name.map { "Evening, \($0)" } ?? "Good evening"
        }
    }
}

/// The full-width card at the top of Home.
struct HeroCard: View {
    let game: Game
    let play: () -> Void

    @Namespace private var glass

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GameArtwork(url: game.heroURL ?? game.posterURL, cornerRadius: Theme.heroRadius)
                .frame(height: 260)
                .overlay {
                    LinearGradient(
                        stops: [.init(color: .black.opacity(0), location: 0.3),
                                .init(color: .black.opacity(0.8), location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(Theme.heroShape)
                }

            VStack(alignment: .leading, spacing: 11) {
                Text(game.genre.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.75))

                Text(game.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                // A glass container lets these two controls share one piece of
                // glass and morph together instead of reading as two stickers.
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: play) {
                            Label("Play", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .glassEffectID("play", in: glass)

                        NavigationLink(value: game) {
                            Text("Details")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .glassEffectID("details", in: glass)
                    }
                }
            }
            .padding(20)
        }
    }
}
