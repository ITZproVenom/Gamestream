import SwiftUI

enum HubBrowseFilter: Hashable {
    case all, mine, browse, forYou, favorites, recents, lists, activity
    case mode(DiscoveryMode)
    case genre(String)

    var title: String {
        switch self {
        case .all: return "Home"
        case .mine: return "Library"
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
    @ObservedObject private var nav = ControllerNavState.shared
    @ObservedObject private var catalogLive = CatalogLiveStore.shared
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var filter: HubBrowseFilter = .all
    @State private var detailGame: CatalogGame?
    @State private var showingLists = false
    @State private var gridFocus: Int?

    private var gridColumns: [GridItem] {
        let gap = appearance.density.carouselSpacing
        return [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)]
    }

    private var primaryChips: [HubBrowseFilter] {
        [.all, .mine, .browse, .forYou, .favorites, .recents, .lists, .activity]
    }

    private var secondaryChips: [HubBrowseFilter] {
        guard appearance.showGenreFilters else { return [] }
        return DiscoveryMode.allCases.map { .mode($0) }
            + GameCatalog.genreNames.map { .genre($0) }
    }

    private var catalogHits: [CatalogGame] { GameCatalog.matches(query) }

    private var filteredGames: [CatalogGame] {
        switch filter {
        case .all: return GameCatalog.games
        case .browse: return GameCatalog.sortedBrowse
        case .mine: return personalGames
        case .forYou: return GameCatalog.forYou(favorites: session.favorites, recents: session.recents)
        case .favorites: return session.favorites.map { GameCatalog.catalog(from: $0) }
        case .recents: return session.recents.map { GameCatalog.catalog(from: $0) }
        case .lists, .activity: return []
        case .mode(let mode): return GameCatalog.games(in: mode)
        case .genre(let name): return GameCatalog.games.filter { $0.genre == name }
        }
    }

    private var personalGames: [CatalogGame] {
        var seen = Set<String>()
        var games: [CatalogGame] = []
        for tracked in session.favorites + session.recents {
            let game = GameCatalog.catalog(from: tracked)
            if seen.insert(game.id.uppercased()).inserted { games.append(game) }
        }
        return games
    }

    private var activeGridGames: [CatalogGame] {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return catalogHits }
        switch filter {
        case .all, .lists, .activity: return []
        default: return filteredGames
        }
    }

    var body: some View {
        HubPage {
            header
            searchField

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults
            } else {
                playNextBanner
                segmentBar
                if appearance.showGenreFilters && !secondaryChips.isEmpty {
                    genreRow
                }
                filterBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let _ = catalogLive.revision
            prewarmVisibleArtwork()
        }
        .onChange(of: catalogLive.revision) { _, _ in
            prewarmVisibleArtwork()
        }
        .onChange(of: nav.token) { _, _ in
            if let action = nav.action { handleGridNav(action) }
        }
        .onChange(of: filter) { _, _ in gridFocus = nil }
        .onChange(of: query) { _, _ in gridFocus = nil }
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GameStream")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Xbox Cloud Gaming")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Button { session.openXboxCloud() } label: {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open Xbox Cloud library")
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search games", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.weight(.medium))
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: appearance.density.sectionSpacing * 0.6) {
            Text(catalogHits.isEmpty ? "No matches" : "Results")
                .font(.title3.weight(.bold))
            if catalogHits.isEmpty {
                Text("No local catalog titles match this search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ScrollViewReader { proxy in
                    LazyVGrid(columns: gridColumns, spacing: appearance.density.carouselSpacing + 4) {
                        ForEach(Array(catalogHits.enumerated()), id: \.element.id) { index, game in
                            poster(game, isFocused: gridFocus == index).id(game.id)
                        }
                    }
                    .onChange(of: gridFocus) { _, newFocus in
                        guard let newFocus, newFocus < catalogHits.count else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(catalogHits[newFocus].id, anchor: .center)
                        }
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
                GameArtView(url: artwork.url(for: next.id), accent: catalog.accent, title: next.title)
                    .frame(width: 56, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Up next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(next.title).font(.headline).lineLimit(1)
                    HStack(spacing: 8) {
                        Button {
                            session.offerPlayNext = false
                            _ = session.playNextQueued()
                        } label: {
                            Text("Play").font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                        }
                        .buttonStyle(.glassProminent)
                        Button { session.offerPlayNext = false } label: {
                            Text("Skip").font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 7)
                        }
                        .buttonStyle(.glass)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var segmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(primaryChips, id: \.self) { chip in
                    Button { filter = chip } label: {
                        Text(chip.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .modifier(HubChipStyle(selected: filter == chip))
                }
            }
        }
    }

    private var genreRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(secondaryChips, id: \.self) { chip in
                    Button { filter = chip } label: {
                        Text(chip.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    .modifier(HubChipStyle(selected: filter == chip))
                }
            }
        }
    }

    @ViewBuilder
    private var filterBody: some View {
        switch filter {
        case .all:
            homeContent
        case .lists:
            GameHubListsSection(showingLists: $showingLists, detailGame: $detailGame)
        case .activity:
            GameHubActivitySection(detailGame: $detailGame)
        default:
            filteredGrid
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        switch appearance.hubLayout {
        case .editorial:
            editorialHome
        case .rails:
            railsHome
        case .grid:
            gridHome
        }
    }

    private var editorialHome: some View {
        VStack(alignment: .leading, spacing: appearance.density.sectionSpacing) {
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
                .frame(height: appearance.density == .compact ? 200 : 280)
                .clipped()
            }

            JumpBackInDock()

            if appearance.showActivityOnHome {
                GameHubActivityBanner(detailGame: $detailGame) { filter = .activity }
            }

            if GameCatalog.featured.count > 1 {
                rail(title: "Featured", games: Array(GameCatalog.featured.dropFirst()))
            }

            shelvesSection
            cloudLibraryButton
        }
    }

    private var railsHome: some View {
        VStack(alignment: .leading, spacing: appearance.density.sectionSpacing) {
            JumpBackInDock()
            featuredCarousel
            if appearance.showActivityOnHome {
                GameHubActivityBanner(detailGame: $detailGame) { filter = .activity }
            }
            shelvesSection
            cloudLibraryButton
        }
    }

    private var gridHome: some View {
        VStack(alignment: .leading, spacing: appearance.density.sectionSpacing) {
            JumpBackInDock()
            HubSectionHeader(title: "All games")
            LazyVGrid(columns: gridColumns, spacing: appearance.density.carouselSpacing + 4) {
                ForEach(GameCatalog.sortedBrowse.prefix(40)) { game in
                    poster(game)
                }
            }
            cloudLibraryButton
        }
    }

    private var featuredCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubSectionHeader(title: "Featured")
            HubCarousel(spacing: appearance.density.carouselSpacing) {
                ForEach(GameCatalog.featured) { game in
                    FeaturedGameCard(
                        game: game,
                        artworkURL: artwork.url(for: game.id),
                        play: { session.playCatalogGame(game) },
                        favorite: { session.toggleFavorite(game.tracked) },
                        isFavorite: { session.isFavorite(game.id) },
                        openDetail: { detailGame = game }
                    )
                    .containerRelativeFrame(.horizontal) { width, _ in
                        HubMetrics.featuredCardWidth(containerWidth: width)
                    }
                    .frame(height: appearance.density == .compact ? 170 : 210)
                    .clipped()
                }
            }
        }
    }

    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: appearance.density.sectionSpacing) {
            GameHubListShelves()
            ForEach(Array(GameCatalog.hubShelves(favorites: session.favorites, recents: session.recents).enumerated()), id: \.offset) { _, row in
                rail(title: row.0, games: row.1)
            }
        }
    }

    private func rail(title: String, games: [CatalogGame]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HubSectionHeader(title: title)
            HubCarousel(spacing: appearance.density.carouselSpacing) {
                ForEach(games) { game in
                    poster(game)
                        .containerRelativeFrame(.horizontal) { width, _ in
                            HubMetrics.posterWidth(
                                containerWidth: width,
                                compact: appearance.density == .compact || appearance.cardStyle == .compact
                            )
                        }
                }
            }
        }
    }

    private var filteredGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HubSectionHeader(title: filter.title)
            if filteredGames.isEmpty {
                Text(emptyCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ScrollViewReader { proxy in
                    LazyVGrid(columns: gridColumns, spacing: appearance.density.carouselSpacing + 4) {
                        ForEach(Array(filteredGames.enumerated()), id: \.element.id) { index, game in
                            poster(game, isFocused: gridFocus == index).id(game.id)
                        }
                    }
                    .onChange(of: gridFocus) { _, newFocus in
                        guard let newFocus, newFocus < filteredGames.count else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(filteredGames[newFocus].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var emptyCopy: String {
        switch filter {
        case .browse: return "The catalog hasn't loaded yet."
        case .mine: return "Star a game or play a title and it will live here."
        case .favorites: return "Star a game to pin it here."
        case .recents: return "Launch a title and it will appear here."
        case .forYou: return "Play or favorite a few games so For You can learn your genres."
        default: return "No titles in this filter."
        }
    }

    private var cloudLibraryButton: some View {
        Button { filter = .browse } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse all games").font(.headline).lineLimit(1)
                    Text("Full native catalog grid").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .buttonStyle(.glass)
    }

    private func poster(_ game: CatalogGame, isFocused: Bool = false) -> some View {
        GamePosterCard(
            game: game,
            artworkURL: artwork.url(for: game.id),
            isFavorite: session.isFavorite(game.id),
            onPlay: { session.playCatalogGame(game) },
            onOpen: { detailGame = game },
            onFavorite: { session.toggleFavorite(game.tracked) }
        )
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func prewarmVisibleArtwork() {
        let firstScreen = Array(
            Set(
                GameCatalog.featured.map(\.id)
                + GameCatalog.sortedBrowse.prefix(16).map(\.id)
            )
        )
        artwork.prefetch(firstScreen)
        for id in firstScreen {
            if let url = artwork.url(for: id) {
                RemoteImageLoader.shared.request(url)
            }
        }
    }

    private func handleGridNav(_ action: ControllerGameNav) {
        let games = activeGridGames
        guard !games.isEmpty else { return }
        if action == .activate {
            guard let gridFocus, gridFocus < games.count else { return }
            HapticManager.impact()
            SoundManager.playTap()
            session.playCatalogGame(games[gridFocus])
            return
        }
        let cols = 2
        var next = gridFocus ?? 0
        switch action {
        case .left: next = max(0, next - 1)
        case .right: next = min(games.count - 1, next + 1)
        case .up: next = max(0, next - cols)
        case .down: next = min(games.count - 1, next + cols)
        default: break
        }
        gridFocus = next
    }
}
