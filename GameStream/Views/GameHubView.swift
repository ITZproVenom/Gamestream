import SwiftUI

enum HubBrowseFilter: Hashable {
    case all
    case mine
    case browse
    case forYou
    case favorites
    case recents
    case lists
    case activity
    case mode(DiscoveryMode)
    case genre(String)

    var title: String {
        switch self {
        case .all: return "All"
        case .mine: return "My Library"
        case .browse: return "All Games"
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
    @ObservedObject private var nav = ControllerNavState.shared
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var filter: HubBrowseFilter = .all
    @State private var detailGame: CatalogGame?
    @State private var showingLists = false
    @State private var gridFocus: Int?
    @State private var scrollProxy: ScrollViewProxy?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    /// Primary chips only — genres & modes live one scroll away, not crammed in.
    private var primaryChips: [HubBrowseFilter] {
        [.all, .mine, .browse, .forYou, .favorites, .recents, .lists, .activity]
    }

    private var secondaryChips: [HubBrowseFilter] {
        DiscoveryMode.allCases.map { .mode($0) }
            + GameCatalog.genreNames.map { .genre($0) }
    }

    private var catalogHits: [CatalogGame] {
        GameCatalog.matches(query)
    }

    private var filteredGames: [CatalogGame] {
        switch filter {
        case .all:
            return GameCatalog.games
        case .browse:
            return GameCatalog.sortedBrowse
        case .mine:
            return personalGames
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

    private var personalGames: [CatalogGame] {
        var seen = Set<String>()
        var games: [CatalogGame] = []
        for tracked in session.favorites + session.recents {
            let game = GameCatalog.catalog(from: tracked)
            if seen.insert(game.id.uppercased()).inserted {
                games.append(game)
            }
        }
        return games
    }

    private var activeGridGames: [CatalogGame] {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return catalogHits
        }
        switch filter {
        case .all, .lists, .activity:
            return []
        default:
            return filteredGames
        }
    }

    private func handleGridNav(_ action: ControllerGameNav) {
        let games = activeGridGames
        guard !games.isEmpty else { return }
        let count = games.count
        if action == .activate {
            guard let gridFocus, gridFocus < count else { return }
            HapticManager.impact()
            SoundManager.playSuccess()
            detailGame = games[gridFocus]
            return
        }
        let current = gridFocus ?? 0
        let next: Int
        switch action {
        case .left: next = max(current - 1, 0)
        case .right: next = min(current + 1, count - 1)
        case .up: next = max(current - 2, 0)
        case .down: next = min(current + 2, count - 1)
        default: return
        }
        guard next != gridFocus else { return }
        gridFocus = next
        HapticManager.tap()
        SoundManager.playTap()
    }

    var body: some View {
        HubPage {
            header
            searchField

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults
            } else {
                JumpBackInDock()
                playNextBanner
                filterChips
                filterBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let firstScreen = GameCatalog.featured.map(\.id)
                + Array(GameCatalog.sortedBrowse.prefix(24)).map(\.id)
            artwork.prefetch(Array(Set(firstScreen)))
        }
        .onChange(of: nav.token) { _, _ in
            if let action = nav.action {
                handleGridNav(action)
            }
        }
        .onChange(of: filter) { _, _ in
            gridFocus = nil
        }
        .onChange(of: query) { _, _ in
            gridFocus = nil
        }
        .onChange(of: gridFocus) { _, _ in
            let games = activeGridGames
            guard let gridFocus, gridFocus < games.count else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy?.scrollTo(games[gridFocus].id, anchor: .center)
            }
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GameStream")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Xbox Cloud Gaming")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                session.openXboxCloud()
            } label: {
                Label("Cloud", systemImage: "cloud.fill")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open Xbox Cloud library")
        }
        .padding(.bottom, 4)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search games", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 17, weight: .medium))
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(catalogHits.isEmpty ? "No catalog matches" : "Matching games")
                .font(.title2.weight(.bold))
                .lineLimit(1)

            if catalogHits.isEmpty {
                Text("No local catalog titles match this search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ScrollViewReader { proxy in
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(Array(catalogHits.enumerated()), id: \.element.id) { index, game in
                            poster(game, isFocused: gridFocus == index)
                                .id(game.id)
                        }
                    }
                    .onAppear { scrollProxy = proxy }
                }
            }

            Button {
                session.openSearch(query: query)
            } label: {
                HStack {
                    Image(systemName: "cloud.fill")
                    Text("Search Xbox Cloud for \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Search Xbox Cloud")
        }
    }

    // MARK: - Up next

    @ViewBuilder
    private var playNextBanner: some View {
        if session.offerPlayNext, let next = session.nextQueuedGame {
            let catalog = GameCatalog.catalog(from: next)
            VStack(alignment: .leading, spacing: 12) {
                Text("Up next")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)

                HStack(spacing: 14) {
                    GameArtView(url: artwork.url(for: next.id), accent: catalog.accent, title: next.title)
                        .frame(width: 64, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(next.title)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)

                        HStack(spacing: 10) {
                            Button {
                                session.offerPlayNext = false
                                _ = session.playNextQueued()
                            } label: {
                                Text("Play next")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.glassProminent)

                            Button {
                                session.offerPlayNext = false
                            } label: {
                                Text("Dismiss")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    // MARK: - Filters

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubCarousel(spacing: 10) {
                ForEach(primaryChips, id: \.self) { chip in
                    chipButton(chip)
                }
            }

            // Modes + genres on a second row so the primary row stays calm
            HubCarousel(spacing: 10) {
                ForEach(secondaryChips, id: \.self) { chip in
                    chipButton(chip)
                }
            }
        }
    }

    private func chipButton(_ chip: HubBrowseFilter) -> some View {
        Button {
            filter = chip
        } label: {
            Text(chip.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .modifier(HubChipStyle(selected: filter == chip))
        .accessibilityLabel(chip.title)
    }

    // MARK: - Body by filter

    @ViewBuilder
    private var filterBody: some View {
        switch filter {
        case .all:
            featuredSection
            GameHubActivityBanner(detailGame: $detailGame) { filter = .activity }
            shelvesSection
            cloudLibraryButton
        case .lists:
            GameHubListsSection(showingLists: $showingLists, detailGame: $detailGame)
        case .activity:
            GameHubActivitySection(detailGame: $detailGame)
        default:
            filteredGrid
        }
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HubSectionHeader(title: "Featured")
            HubCarousel(spacing: 16) {
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
                    .frame(height: 220)
                }
            }
        }
    }

    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            GameHubListShelves()
            ForEach(Array(GameCatalog.hubShelves(favorites: session.favorites, recents: session.recents).enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 14) {
                    HubSectionHeader(title: row.0)
                    HubCarousel(spacing: 14) {
                        ForEach(row.1) { game in
                            poster(game)
                                .containerRelativeFrame(.horizontal) { width, _ in
                                    HubMetrics.posterWidth(containerWidth: width)
                                }
                        }
                    }
                }
            }
        }
    }

    private var filteredGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            HubSectionHeader(title: filter.title)

            if filteredGames.isEmpty {
                Text(emptyCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ScrollViewReader { proxy in
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(Array(filteredGames.enumerated()), id: \.element.id) { index, game in
                            poster(game, isFocused: gridFocus == index)
                                .id(game.id)
                        }
                    }
                    .onAppear { scrollProxy = proxy }
                }
            }
        }
    }

    private var emptyCopy: String {
        switch filter {
        case .browse: return "The catalog hasn't loaded yet. Pull to try again."
        case .mine: return "Star a game or play a title and it will live here."
        case .favorites: return "Star a game to pin it here."
        case .recents: return "Launch a title and it will appear here."
        case .forYou: return "Play or favorite a few games so For You can learn your genres."
        default: return "No titles in this filter."
        }
    }

    private var cloudLibraryButton: some View {
        Button {
            filter = .browse
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Browse all games")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Every catalog title in a native grid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Browse all catalog games")
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }
}
