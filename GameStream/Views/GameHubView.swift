import SwiftUI

struct GameHubView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var artwork = ArtworkStore.shared
    @ObservedObject private var hub = HubState.shared
    @State private var featuredIndex = 0
    @State private var hubQuery = ""

    private var featured: [CatalogGame] { GameCatalog.featured }
    private var shelves: [(String, [CatalogGame])] {
        GameCatalog.shelves(favorites: session.favorites, recents: session.recents)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                searchField
                featuredCarousel
                ForEach(shelves, id: \.0) { shelf in
                    gameShelf(title: shelf.0, games: shelf.1)
                }
                xboxCloudRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            artwork.prefetch(GameCatalog.games.map(\ .id) + session.favorites.map(\ .id) + session.recents.map(\ .id))
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

    private var featuredCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Featured").font(.title3.weight(.semibold)).lineLimit(1)
            TabView(selection: $featuredIndex) {
                ForEach(Array(featured.enumerated()), id: \.element.id) { index, game in
                    FeaturedGameCard(game: game, artworkURL: artwork.url(for: game.id), play: { session.playCatalogGame(game) }, favorite: { session.toggleFavorite(game.tracked) }, isFavorite: { session.isFavorite(game.id) })
                    .padding(.horizontal, 2)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 210)
        }
    }

    private func gameShelf(title: String, games: [CatalogGame]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(games) { game in
                        GamePosterCard(game: game, artworkURL: artwork.url(for: game.id), isFavorite: session.isFavorite(game.id), onPlay: { session.playCatalogGame(game) }, onOpen: { session.openCatalogGame(game) }, onFavorite: { session.toggleFavorite(game.tracked) })
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
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GameArtView(url: artworkURL, accent: game.accent, title: game.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        .frame(width: 132, height: 176)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain)
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star").font(.system(size: 11, weight: .bold)).padding(6).background(.ultraThinMaterial, in: Circle())
                }.buttonStyle(.plain).padding(8)
            }
            Text(game.title).font(.caption.weight(.semibold)).lineLimit(2).frame(width: 132, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(game.provider).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onPlay) { Text("Play").font(.caption2.weight(.semibold)).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 5) }.buttonStyle(.glassProminent)
            }.frame(width: 132)
        }.frame(width: 132)
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
