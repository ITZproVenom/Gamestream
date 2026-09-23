import SwiftUI

/// Clean-slate home / library surface. Calls locked play path only.
struct HomeFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var catalogLive = CatalogLiveStore.shared
    var onOpenGame: (CatalogGame) -> Void

    private var shelves: [(String, [CatalogGame])] {
        _ = catalogLive.revision
        return GameCatalog.shelves(favorites: session.favorites, recents: session.recents)
    }

    private var featured: CatalogGame? {
        GameCatalog.featured.first ?? GameCatalog.games.first
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - 40, 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let hero = featured {
                        HeroCard(
                            game: hero,
                            artworkURL: ArtworkStore.shared.url(for: hero.id) ?? hero.posterURL,
                            onPlay: { session.playCatalogGame(hero) },
                            onOpen: { onOpenGame(hero) },
                            onFavorite: { session.toggleFavorite(hero.tracked) },
                            isFavorite: session.isFavorite(hero.id)
                        )
                        .frame(height: min(360, geo.size.height * 0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    ForEach(Array(shelves.enumerated()), id: \.offset) { _, shelf in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(shelf.0)
                                .font(.title3.weight(.bold))
                                .lineLimit(1)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(shelf.1) { game in
                                        PosterCard(
                                            game: game,
                                            artworkURL: ArtworkStore.shared.url(for: game.id) ?? game.posterURL,
                                            isFavorite: session.isFavorite(game.id),
                                            onPlay: { session.playCatalogGame(game) },
                                            onOpen: { onOpenGame(game) },
                                            onFavorite: { session.toggleFavorite(game.tracked) }
                                        )
                                        .frame(width: min(140, width * 0.38))
                                    }
                                }
                            }
                            .frame(height: 240)
                            .clipped()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            ArtworkStore.shared.prefetch(GameCatalog.games.prefix(24).map(\n.id))
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library")
                    .font(.largeTitle.weight(.bold))
                if let label = session.accountLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
