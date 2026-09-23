import SwiftUI

/// Full native hub — layout scales from container width (Dynamic Island phones ~390–430pt).
struct HomeFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var catalogLive = CatalogLiveStore.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @State private var filter: HubFilter = .home
    @State private var showingLists = false
    var onOpenGame: (CatalogGame) -> Void

    private var primaryChips: [HubFilter] {
        [.home, .library, .browse, .forYou, .favorites, .recents, .lists, .activity]
    }

    private var secondaryChips: [HubFilter] {
        guard appearance.showGenreFilters else { return [] }
        return DiscoveryMode.allCases.map { .mode($0) }
            + GameCatalog.genreNames.prefix(10).map { .genre($0) }
    }

    private var filteredGames: [CatalogGame] {
        _ = catalogLive.revision
        switch filter {
        case .home:
            return GameCatalog.games
        case .browse:
            return GameCatalog.sortedBrowse
        case .library:
            var seen = Set<String>()
            var out: [CatalogGame] = []
            for t in session.favorites + session.recents {
                let g = GameCatalog.catalog(from: t)
                if seen.insert(g.id.uppercased()).inserted { out.append(g) }
            }
            return out
        case .forYou:
            return GameCatalog.forYou(favorites: session.favorites, recents: session.recents)
        case .favorites:
            return session.favorites.map { GameCatalog.catalog(from: $0) }
        case .recents:
            return session.recents.map { GameCatalog.catalog(from: $0) }
        case .lists, .activity:
            return []
        case .mode(let mode):
            return GameCatalog.games(in: mode)
        case .genre(let name):
            return GameCatalog.games.filter { $0.genre == name }
        }
    }

    /// Prefer a featured title that already has art; fall back to any featured / first game.
    private var heroGame: CatalogGame? {
        _ = artwork.urls
        let featured = GameCatalog.featured
        if let hit = featured.first(where: { artwork.url(for: $0.id) != nil || $0.posterURL != nil }) {
            return hit
        }
        return featured.first ?? GameCatalog.games.first
    }

    var body: some View {
        GeometryReader { geo in
            let pageW = max(geo.size.width, 1)
            let railW = LayoutMetrics.railPosterWidth(containerWidth: pageW)
            let gridW = LayoutMetrics.gridPosterWidth(containerWidth: pageW)
            let rowH = LayoutMetrics.cardHeight(posterWidth: railW)
            // Fixed hero height for this phone class — never pageH-fraction (that caused overlap)
            let heroH: CGFloat = appearance.density == .compact ? 196 : 220

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    PlayNextBannerFeature()
                    chipRow(primaryChips)
                    if !secondaryChips.isEmpty {
                        chipRow(secondaryChips, compact: true)
                    }
                    filterBody(railW: railW, gridW: gridW, rowH: rowH, heroH: heroH)
                }
                .padding(.horizontal, LayoutMetrics.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, LayoutMetrics.tabBarClearance)
                .frame(maxWidth: pageW, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .refreshable { session.refreshXboxPlayHistory(force: true) }
        }
        .onAppear {
            let ids = GameCatalog.featured.map(\.id)
                + Array(GameCatalog.sortedBrowse.prefix(40)).map(\.id)
                + session.recents.map(\.id)
                + session.favorites.map(\.id)
            artwork.prefetch(ids)
        }
        .sheet(isPresented: $showingLists) {
            NavigationStack {
                ListsFeature(onOpenGame: onOpenGame)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingLists = false }
                        }
                    }
            }
            .environmentObject(session)
            .presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GameStream")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Xbox Cloud Gaming")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                session.openXboxCloud()
            } label: {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open Xbox Cloud")
        }
    }

    private func chipRow(_ chips: [HubFilter], compact: Bool = false) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            filter = chip
                        }
                    } label: {
                        Text(chip.title)
                            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .buttonStyle(.plain)
                    .modifier(FeatureChipStyle(selected: filter == chip))
                }
            }
        }
    }

    @ViewBuilder
    private func filterBody(railW: CGFloat, gridW: CGFloat, rowH: CGFloat, heroH: CGFloat) -> some View {
        switch filter {
        case .home:
            homeContent(railW: railW, rowH: rowH, heroH: heroH)
        case .lists:
            ListsFeature(onOpenGame: onOpenGame)
        case .activity:
            ActivityFeature(onOpenGame: onOpenGame)
        default:
            filteredGrid(cellW: gridW)
        }
    }

    private func homeContent(railW: CGFloat, rowH: CGFloat, heroH: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            JumpBackInFeature(onOpen: onOpenGame)

            if appearance.showActivityOnHome {
                ActivityBannerFeature {
                    filter = .activity
                }
            }

            if let hero = heroGame {
                HeroCard(
                    game: hero,
                    artworkURL: artwork.url(for: hero.id) ?? hero.posterURL,
                    onPlay: { session.playCatalogGame(hero) },
                    onOpen: { onOpenGame(hero) },
                    onFavorite: { session.toggleFavorite(hero.tracked) },
                    isFavorite: session.isFavorite(hero.id)
                )
                .frame(maxWidth: .infinity)
                .frame(height: heroH)
                .clipped()
                // Keep the next shelf from sliding under the hero
                .padding(.bottom, 4)
            }

            ForEach(Array(GameCatalog.hubShelves(favorites: session.favorites, recents: session.recents).enumerated()), id: \.offset) { _, row in
                rail(title: row.0, games: row.1, posterW: railW, rowH: rowH)
            }

            Button {
                filter = .browse
            } label: {
                HStack {
                    Image(systemName: "square.grid.2x2.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse all games").font(.headline)
                        Text("Full native catalog").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.glass)
        }
    }

    private func filteredGrid(cellW: CGFloat) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: LayoutMetrics.gridSpacing),
            GridItem(.flexible(), spacing: LayoutMetrics.gridSpacing)
        ]
        return VStack(alignment: .leading, spacing: 14) {
            Text(filter.title)
                .font(.title2.weight(.bold))
            if filteredGames.isEmpty {
                FeatureEmptyCard(message: emptyCopy)
            } else {
                LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
                    ForEach(filteredGames) { game in
                        PosterCard(
                            game: game,
                            artworkURL: artwork.url(for: game.id) ?? game.posterURL,
                            isFavorite: session.isFavorite(game.id),
                            onPlay: { session.playCatalogGame(game) },
                            onOpen: { onOpenGame(game) },
                            onFavorite: { session.toggleFavorite(game.tracked) }
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
    }

    private var emptyCopy: String {
        switch filter {
        case .browse: return "Catalog is still loading."
        case .library: return "Star or play a game and it will appear here."
        case .favorites: return "Star a game to pin it here."
        case .recents: return "Play a title, or wait for Xbox recents after sign-in."
        case .forYou: return "Play a few games so For You can learn your taste."
        default: return "Nothing in this filter yet."
        }
    }

    private func rail(title: String, games: [CatalogGame], posterW: CGFloat, rowH: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: LayoutMetrics.railSpacing) {
                    ForEach(games) { game in
                        PosterCard(
                            game: game,
                            artworkURL: artwork.url(for: game.id) ?? game.posterURL,
                            isFavorite: session.isFavorite(game.id),
                            onPlay: { session.playCatalogGame(game) },
                            onOpen: { onOpenGame(game) },
                            onFavorite: { session.toggleFavorite(game.tracked) }
                        )
                        .frame(width: posterW, height: rowH, alignment: .top)
                        .clipped()
                    }
                }
            }
            .frame(height: rowH, alignment: .top)
            .clipped()
        }
    }
}
