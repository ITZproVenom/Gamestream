import SwiftUI

/// Personal library: favorites, recents, queue, and quick filters.
struct LibraryFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var artwork = ArtworkStore.shared
    @ObservedObject private var queue = PlayQueueStore.shared
    @State private var segment: Segment = .all
    var onOpenGame: (CatalogGame) -> Void

    enum Segment: String, CaseIterable {
        case all = "All"
        case favorites = "Favorites"
        case recents = "Recents"
        case queue = "Queue"
    }

    private var games: [CatalogGame] {
        switch segment {
        case .all:
            var seen = Set<String>()
            var out: [CatalogGame] = []
            for t in session.favorites + session.recents {
                let g = GameCatalog.catalog(from: t)
                if seen.insert(g.id.uppercased()).inserted { out.append(g) }
            }
            return out
        case .favorites:
            return session.favorites.map { GameCatalog.catalog(from: $0) }
        case .recents:
            return session.recents.map { GameCatalog.catalog(from: $0) }
        case .queue:
            return queue.games.map { GameCatalog.catalog(from: $0) }
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Library")
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, 8)

                if let label = session.accountLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Segment.allCases, id: \.self) { seg in
                            Button {
                                segment = seg
                            } label: {
                                Text(seg.rawValue)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .modifier(FeatureChipStyle(selected: segment == seg))
                        }
                    }
                }

                if games.isEmpty {
                    FeatureEmptyCard(message: emptyMessage)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(games) { game in
                            PosterCard(
                                game: game,
                                artworkURL: artwork.url(for: game.id) ?? game.posterURL,
                                isFavorite: session.isFavorite(game.id),
                                onPlay: { session.playCatalogGame(game) },
                                onOpen: { onOpenGame(game) },
                                onFavorite: { session.toggleFavorite(game.tracked) }
                            )
                            .contextMenu {
                                Button(session.isQueued(game.id) ? "Remove from queue" : "Add to queue") {
                                    session.toggleQueue(game.tracked)
                                }
                                if segment == .recents {
                                    Button("Remove from recents", role: .destructive) {
                                        session.removeRecent(game.tracked)
                                    }
                                }
                            }
                        }
                    }
                }

                if segment == .queue, !queue.games.isEmpty {
                    Button {
                        session.clearQueue()
                    } label: {
                        Text("Clear queue")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            artwork.prefetch(games.prefix(24).map(\.id))
        }
    }

    private var emptyMessage: String {
        switch segment {
        case .all: return "Star or play a game and it will appear in your library."
        case .favorites: return "Star a game to pin it here."
        case .recents: return "Play a title to build recents."
        case .queue: return "Queue games from details or long-press a poster."
        }
    }
}
