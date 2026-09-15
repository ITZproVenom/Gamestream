import SwiftUI

enum HubBrowseFilter: Hashable {
    case all
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
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var filter: HubBrowseFilter = .all
    @State private var detailGame: CatalogGame?
    @State private var showingLists = false

    private var chips: [HubBrowseFilter] {
        var items: [HubBrowseFilter] = [.all, .forYou, .favorites, .recents, .lists, .activity]
        items.append(contentsOf: DiscoveryMode.allCases.map { .mode($0) })
        items.append(contentsOf: GameCatalog.genreNames.map { .genre($0) })
        return items
    }

    private var catalogHits: [CatalogGame] {
        GameCatalog.matches(query)
    }

    private var filteredGames: [CatalogGame] {
        switch filter {
        case .all:
            return GameCatalog.games
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

    var body: some View {
        ZStack {
            AnimatedBackground().ignoresSafeArea()
            HubPage {
                header
                searchField
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResults
                } else {
                    JumpBackInDock()
                    playNextBanner
                    chipRow
                    filterBody
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            artwork.prefetch(GameCatalog.games.map(\.id))
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GameStream")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
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
                Text("Cloud")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
            TextField("Search GameHub", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16, weight: .medium))
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear GameHub search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(catalogHits.isEmpty ? "No catalog matches" : "Matching games")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            if catalogHits.isEmpty {
                Text("No local catalog titles match this search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(catalogHits) { game in
                        poster(game)
                    }
                }
            }
            Button {
                session.openSearch(query: query)
            } label: {
                Text("Search Xbox Cloud for \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Search Xbox Cloud")
        }
    }

    @ViewBuilder
    private var playNextBanner: some View {
        if session.offerPlayNext, let next = session.nextQueuedGame {
            let catalog = GameCatalog.catalog(from: next)
            VStack(alignment: .leading, spacing: 10) {
                Text("Up next")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 12) {
                    GameArtView(url: artwork.url(for: next.id), accent: catalog.accent, title: next.title)
                        .frame(width: 52, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(next.title)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        HStack(spacing: 8) {
                            Button {
                                session.offerPlayNext = false
                                _ = session.playNextQueued()
                            } label: {
                                Text("Play next")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.glassProminent)
                            Button {
                                session.offerPlayNext = false
                            } label: {
                                Text("Dismiss")
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var chipRow: some View {
        HubCarousel(spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Button {
                    filter = chip
                } label: {
                    Text(chip.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .modifier(HubChipStyle(selected: filter == chip))
                .accessibilityLabel(chip.title)
            }
        }
    }

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
        VStack(alignment: .leading, spacing: 10) {
            Text("Featured")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            HubCarousel(spacing: 14) {
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
                    .frame(height: 176)
                }
            }
        }
    }

    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            GameHubListShelves()
            ForEach(Array(GameCatalog.hubShelves(favorites: session.favorites, recents: session.recents).enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 10) {
                    Text(row.0)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    HubCarousel(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            if filteredGames.isEmpty {
                Text(emptyCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(filteredGames) { game in
                        poster(game)
                    }
                }
            }
        }
    }

    private var emptyCopy: String {
        switch filter {
        case .favorites: return "Star a game to pin it here."
        case .recents: return "Launch a title and it will appear here."
        case .forYou: return "Play or favorite a few games so For You can learn your genres."
        default: return "No titles in this filter."
        }
    }

    private var cloudLibraryButton: some View {
        Button {
            session.openXboxCloud()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Xbox Cloud library")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Browse every title in the official catalog")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
            }
            .padding(16)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Open full Xbox Cloud library")
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
