import SwiftUI

enum HubBrowseFilter: Hashable {
    case all
    case favorites
    case recents
    case genre(String)

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .recents: return "Recents"
        case .genre(let name): return name
        }
    }
}

struct GameHubView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var artwork = ArtworkStore.shared
    @State private var featuredIndex = 0
    @State private var hubQuery = ""
    @State private var detailGame: CatalogGame?
    @State private var filter: HubBrowseFilter = .all

    private var featured: [CatalogGame] { GameCatalog.featured }
    private var shelves: [(String, [CatalogGame])] {
        GameCatalog.shelves(favorites: session.favorites, recents: session.recents)
    }
    private var liveMatches: [CatalogGame] {
        GameCatalog.matches(hubQuery)
    }
    private var isFiltering: Bool {
        !hubQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var genreChips: [HubBrowseFilter] {
        GameCatalog.genreNames.map { .genre($0) }
    }
    private var filteredGames: [CatalogGame] {
        switch filter {
        case .all:
            return GameCatalog.games
        case .favorites:
            return session.favorites.map { GameCatalog.catalog(from: $0) }
        case .recents:
            return session.recents.map { GameCatalog.catalog(from: $0) }
        case .genre(let name):
            return GameCatalog.games.filter { $0.genre == name }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchField
                if isFiltering {
                    liveResults
                } else {
                    if filter == .all, let continueGame = session.continueGame {
                        continueHero(GameCatalog.catalog(from: continueGame))
                    }
                    filterChips
                    if filter == .all {
                        featuredCarousel
                        ForEach(shelves, id: \.0) { shelf in
                            gameShelf(title: shelf.0, games: shelf.1, allowsRemoveRecent: shelf.0 == "Continue playing")
                        }
                        xboxCloudRow
                    } else {
                        filteredGrid
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $detailGame) { game in
            GameDetailView(game: game) { detailGame = nil }
                .environmentObject(session)
        }
        .onAppear {
            let ids = GameCatalog.games.map { $0.id } + session.favorites.map { $0.id } + session.recents.map { $0.id }
            artwork.prefetch(ids)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GameStream")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
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
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open Xbox Cloud page")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search games", text: $hubQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { submitHubSearch() }
            if !hubQuery.isEmpty {
                Button { hubQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all)
                chip(.favorites)
                chip(.recents)
                ForEach(genreChips, id: \.self) { item in
                    chip(item)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Browse filters")
    }

    private func chip(_ item: HubBrowseFilter) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                filter = item
            }
        } label: {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .modifier(HubChipStyle(selected: filter == item))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(filter == item ? .isSelected : [])
    }

    private func continueHero(_ game: CatalogGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue playing")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 12) {
                Button { detailGame = game } label: {
                    GameArtView(url: artwork.url(for: game.id), accent: game.accent, title: game.title)
                        .frame(width: 72, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(game.title) details")

                VStack(alignment: .leading, spacing: 8) {
                    Text(game.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(game.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { session.playCatalogGame(game) } label: {
                            Text("Resume")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Resume \(game.title)")

                        Button { session.toggleFavorite(game.tracked) } label: {
                            Image(systemName: session.isFavorite(game.id) ? "star.fill" : "star")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 36, height: 34)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(session.isFavorite(game.id) ? "Remove favorite" : "Add favorite")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var filteredGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(filter.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Text("\(filteredGames.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if filteredGames.isEmpty {
                emptyFilterState
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(filteredGames) { game in
                        GamePosterCard(
                            game: game,
                            artworkURL: artwork.url(for: game.id),
                            isFavorite: session.isFavorite(game.id),
                            onPlay: { session.playCatalogGame(game) },
                            onOpen: { detailGame = game },
                            onFavorite: { session.toggleFavorite(game.tracked) }
                        )
                        .frame(maxWidth: .infinity)
                        .contextMenu {
                            Button { session.playCatalogGame(game) } label: {
                                Label("Play now", systemImage: "play.fill")
                            }
                            Button { session.toggleFavorite(game.tracked) } label: {
                                Label(session.isFavorite(game.id) ? "Remove favorite" : "Add favorite", systemImage: session.isFavorite(game.id) ? "star.slash" : "star")
                            }
                            if filter == .recents {
                                Button(role: .destructive) {
                                    session.removeRecent(game.tracked)
                                } label: {
                                    Label("Remove from recents", systemImage: "clock.badge.xmark")
                                }
                            }
                        }
                    }
                }
            }

            if filter == .favorites || filter == .recents {
                xboxCloudRow
            }
        }
    }

    private var emptyFilterState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyTitle)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(emptyBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyTitle: String {
        switch filter {
        case .favorites: return "No favorites yet"
        case .recents: return "Nothing played yet"
        default: return "No titles here"
        }
    }

    private var emptyBody: String {
        switch filter {
        case .favorites:
            return "Star a game from the hub, search, or stream chrome to pin it here."
        case .recents:
            return "Launch a title and it will appear in Recents so you can resume quickly."
        default:
            return "Try another filter or search Xbox Cloud for more games."
        }
    }

    private var liveResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(liveMatches.isEmpty ? "No catalog matches" : "Matching games")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if liveMatches.isEmpty {
                Text("No titles in the local catalog match this search. Search the full Xbox Cloud library instead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(liveMatches) { game in
                        GamePosterCard(
                            game: game,
                            artworkURL: artwork.url(for: game.id),
                            isFavorite: session.isFavorite(game.id),
                            onPlay: { session.playCatalogGame(game) },
                            onOpen: { detailGame = game },
                            onFavorite: { session.toggleFavorite(game.tracked) }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Button {
                submitHubSearch()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    Text("Search Xbox Cloud")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
            }
            .buttonStyle(.glassProminent)
            .accessibilityLabel("Search Xbox Cloud")
        }
    }

    private var featuredCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Featured").font(.title3.weight(.semibold)).lineLimit(1)
            TabView(selection: $featuredIndex) {
                ForEach(Array(featured.enumerated()), id: \.element.id) { index, game in
                    FeaturedGameCard(
                        game: game,
                        artworkURL: artwork.url(for: game.id),
                        play: { session.playCatalogGame(game) },
                        favorite: { session.toggleFavorite(game.tracked) },
                        isFavorite: { session.isFavorite(game.id) },
                        openDetail: { detailGame = game }
                    )
                    .padding(.horizontal, 2)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 210)
        }
    }

    private func gameShelf(title: String, games: [CatalogGame], allowsRemoveRecent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(games) { game in
                        GamePosterCard(
                            game: game,
                            artworkURL: artwork.url(for: game.id),
                            isFavorite: session.isFavorite(game.id),
                            onPlay: { session.playCatalogGame(game) },
                            onOpen: { detailGame = game },
                            onFavorite: { session.toggleFavorite(game.tracked) }
                        )
                        .frame(width: 132)
                        .contextMenu {
                            if allowsRemoveRecent {
                                Button(role: .destructive) {
                                    session.removeRecent(game.tracked)
                                } label: {
                                    Label("Remove from recents", systemImage: "clock.badge.xmark")
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var xboxCloudRow: some View {
        Button { session.openXboxCloud() } label: {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Xbox Cloud library").font(.headline).lineLimit(1)
                    Text("Browse every title in the official catalog").font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
            }
            .padding(16)
        }
        .buttonStyle(.glass)
    }

    private func submitHubSearch() {
        let query = hubQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        session.updateSearchDraft(query)
        SessionStore.rememberSearch(query)
        session.requestedTab = .search
    }
}

struct FeaturedGameCard: View {
    let game: CatalogGame
    let artworkURL: URL?
    let play: () -> Void
    let favorite: () -> Void
    let isFavorite: () -> Bool
    var openDetail: () -> Void = {}
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: openDetail) {
                GameArtView(url: artworkURL, accent: game.accent, title: game.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                Text(game.provider).font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.ultraThinMaterial, in: Capsule()).lineLimit(1)
                Text(game.title).font(.title2.weight(.bold)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
                Text(game.tagline).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                HStack(spacing: 8) {
                    Button(action: play) { Text("Play").font(.subheadline.weight(.semibold)).lineLimit(1).padding(.horizontal, 16).padding(.vertical, 8) }.buttonStyle(.glassProminent)
                    Button(action: favorite) { Image(systemName: isFavorite() ? "star.fill" : "star").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 34) }.buttonStyle(.glass)
                }
            }
            .padding(16)
        }
    }
}

struct GamePosterCard: View {
    let game: CatalogGame
    let artworkURL: URL?
    let isFavorite: Bool
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onFavorite: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    GameArtView(url: artworkURL, accent: game.accent, title: game.title)
                        .frame(maxWidth: .infinity)
                        .frame(height: 176)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain)
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star").font(.system(size: 11, weight: .bold)).padding(6).background(.ultraThinMaterial, in: Circle())
                }.buttonStyle(.plain).padding(8)
            }
            Text(game.title).font(.caption.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(game.provider).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(action: onPlay) { Text("Play").font(.caption2.weight(.semibold)).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 5) }.buttonStyle(.glassProminent)
            }
        }
    }
}

struct GameArtView: View {
    let url: URL?
    let accent: UInt32
    let title: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(hex: accent).gradient)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: artFallback
                    }
                }
            } else { artFallback }
        }.clipped()
    }
    private var artFallback: some View {
        Text(String(title.prefix(1))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
    }
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

private struct HubChipStyle: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}
