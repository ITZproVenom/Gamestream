import SwiftUI

enum HubBrowseFilter: Hashable {
    case home, library, browse, forYou, favorites, recents, lists, activity
    case mode(DiscoveryMode)
    case genre(String)

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .browse: return "Browse"
        case .forYou: return "For You"
        case .favorites: return "Favorites"
        case .recents: return "Recents"
        case .lists: return "Lists"
        case .activity: return "Activity"
        case .mode(let mode): return mode.title
        case .genre(let name): return name
        }
    }
}

struct GameHubView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var artwork = ArtworkStore.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @ObservedObject private var catalogLive = CatalogLiveStore.shared
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var filter: HubBrowseFilter = .home
    @State private var detailGame: CatalogGame?
    @State private var showingLists = false
    @Environment(\.hubContentWidth) private var hubWidth

    private var primaryChips: [HubBrowseFilter] {
        [.home, .library, .browse, .forYou, .favorites, .recents, .lists, .activity]
    }

    private var secondaryChips: [HubBrowseFilter] {
        guard appearance.showGenreFilters else { return [] }
        return DiscoveryMode.allCases.map { .mode($0) }
            + GameCatalog.genreNames.prefix(10).map { .genre($0) }
    }

    private var catalogHits: [CatalogGame] { GameCatalog.matches(query) }

    private var filteredGames: [CatalogGame] {
        switch filter {
        case .home: return GameCatalog.games
        case .browse: return GameCatalog.sortedBrowse
        case .library:
            var seen = Set<String>()
            var out: [CatalogGame] = []
            for t in session.favorites + session.recents {
                let g = GameCatalog.catalog(from: t)
                if seen.insert(g.id.uppercased()).inserted { out.append(g) }
            }
            return out
        case .forYou: return GameCatalog.forYou(favorites: session.favorites, recents: session.recents)
        case .favorites: return session.favorites.map { GameCatalog.catalog(from: $0) }
        case .recents: return session.recents.map { GameCatalog.catalog(from: $0) }
        case .lists, .activity: return []
        case .mode(let mode): return GameCatalog.games(in: mode)
        case .genre(let name): return GameCatalog.games.filter { $0.genre == name }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    }

    private var posterW: CGFloat {
        HubMetrics.posterWidth(
            containerWidth: max(hubWidth, 320),
            compact: appearance.density == .compact || appearance.cardStyle == .compact
        )
    }

    var body: some View {
        HubPage {
            let _ = catalogLive.revision
            header
            searchField

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults
            } else {
                playNextBanner
                chipRow(primaryChips)
                if !secondaryChips.isEmpty {
                    chipRow(secondaryChips, compact: true)
                }
                filterBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { session.refreshXboxPlayHistory(force: true) }
        .onAppear {
            artwork.prefetch(GameCatalog.featured.map(\.id) + Array(GameCatalog.sortedBrowse.prefix(40)).map(\.id))
            artwork.prefetch(session.recents.map(\.id))
        }
        .sheet(item: $detailGame) { game in
            GameDetailView(game: game) { detailGame = nil }
                .environmentObject(session)
        }
        .sheet(isPresented: $showingLists) {
            ListsBrowserView(
                onPlay: { session.playCatalogGame($0) },
                onOpen: { detailGame = $0 }
            )
            .environmentObject(session)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GameStream")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("Xbox Cloud Gaming")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { session.openXboxCloud() } label: {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open Xbox Cloud")
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search games", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chipRow(_ chips: [HubBrowseFilter], compact: Bool = false) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button { filter = chip } label: {
                        Text(chip.title)
                            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, compact ? 12 : 14)
                            .padding(.vertical, compact ? 7 : 9)
                    }
                    .modifier(HubChipStyle(selected: filter == chip))
                }
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(catalogHits.isEmpty ? "No matches" : "Results")
                .font(.title3.weight(.bold))
            if catalogHits.isEmpty {
                Text("No local titles match. Try Xbox Cloud search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(catalogHits) { game in
                        poster(game)
                    }
                }
            }
            Button { session.openSearch(query: query) } label: {
                Label("Search Xbox Cloud", systemImage: "cloud.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var playNextBanner: some View {
        if session.offerPlayNext, let next = session.nextQueuedGame {
            let catalog = GameCatalog.catalog(from: next)
            HStack(spacing: 14) {
                GameArtView(url: artwork.url(for: next.id), accent: catalog.accent, title: catalog.title)
                    .frame(width: 52, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Up next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(catalog.title).font(.headline).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    session.offerPlayNext = false
                    _ = session.playNextQueued()
                } label: {
                    Text("Play").font(.caption.weight(.bold)).padding(.horizontal, 14).padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var filterBody: some View {
        switch filter {
        case .home:
            homeContent
        case .lists:
            GameHubListsSection(showingLists: $showingLists, detailGame: $detailGame)
        case .activity:
            GameHubActivitySection(detailGame: $detailGame)
        default:
            filteredGrid
        }
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            JumpBackInDock()

            if appearance.showActivityOnHome {
                GameHubActivityBanner(detailGame: $detailGame) { filter = .activity }
            }

            if let hero = GameCatalog.featured.first {
                FeaturedGameCard(
                    game: hero,
                    artworkURL: artwork.url(for: hero.id),
                    play: { session.playCatalogGame(hero) },
                    favorite: { session.toggleFavorite(hero.tracked) },
                    isFavorite: { session.isFavorite(hero.id) },
                    openDetail: { detailGame = hero }
                )
                .frame(maxWidth: .infinity)
                .frame(height: appearance.density == .compact ? 200 : 236)
                .clipped()
            }

            ForEach(Array(GameCatalog.hubShelves(favorites: session.favorites, recents: session.recents).enumerated()), id: \.offset) { _, row in
                rail(title: row.0, games: row.1)
            }

            Button { filter = .browse } label: {
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

    private var filteredGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(filter.title)
                .font(.title2.weight(.bold))
            if filteredGames.isEmpty {
                Text(emptyCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(filteredGames) { game in
                        poster(game)
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

    private func rail(title: String, games: [CatalogGame]) -> some View {
        let height = HubMetrics.posterRowHeight(posterWidth: posterW)
        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
            HubCarousel(spacing: 12, rowHeight: height) {
                ForEach(games) { game in
                    poster(game)
                        .frame(width: posterW)
                }
            }
        }
    }

    private func poster(_ game: CatalogGame) -> some View {
        GamePosterCard(
            game: game,
            artworkURL: artwork.url(for: game.id),
            isFavorite: session.isFavorite(game.id),
            onPlay: { session.playCatalogGame(game) },
            onOpen: { detailGame = game },
            onFavorite: { session.toggleFavorite(game.tracked) }
        )
    }
}
