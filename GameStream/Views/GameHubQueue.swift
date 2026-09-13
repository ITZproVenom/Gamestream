import SwiftUI

struct GameHubQueueShelf: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var queue = PlayQueueStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @Binding var detailGame: CatalogGame?

    var body: some View {
        if !queue.games.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Up Next")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        _ = session.playNextQueued()
                    } label: {
                        Text("Play next")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Play next queued game")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(queue.games) { game in
                            let catalog = GameCatalog.catalog(from: game)
                            GamePosterCard(
                                game: catalog,
                                artworkURL: artwork.url(for: game.id),
                                isFavorite: session.isFavorite(game.id),
                                onPlay: { session.playGame(game) },
                                onOpen: { detailGame = catalog },
                                onFavorite: { session.toggleFavorite(game) }
                            )
                            .frame(width: 132)
                            .contextMenu {
                                Button { session.playGame(game) } label: {
                                    Label("Play now", systemImage: "play.fill")
                                }
                                Button(role: .destructive) { session.dequeue(game) } label: {
                                    Label("Remove from Up Next", systemImage: "text.badge.minus")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
