import SwiftUI

struct GameDetailsFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var collections = CollectionStore.shared
    @Environment(\.dismiss) private var dismiss
    let game: CatalogGame

    private var related: [CatalogGame] {
        GameCatalog.related(to: game, limit: 8)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RemoteImage(url: ArtworkStore.shared.url(for: game.id) ?? game.posterURL) {
                    Color(hex: game.accent)
                }
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text(game.title)
                    .font(.title.weight(.bold))
                Text(game.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(game.genre)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                    Text(game.provider)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                }

                HStack(spacing: 12) {
                    Button {
                        session.playCatalogGame(game)
                        dismiss()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        session.toggleFavorite(game.tracked)
                    } label: {
                        Image(systemName: session.isFavorite(game.id) ? "star.fill" : "star")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.glass)

                    Button {
                        session.toggleQueue(game.tracked)
                    } label: {
                        Image(systemName: session.isQueued(game.id) ? "text.badge.minus" : "text.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.glass)
                }

                Button {
                    session.openCloudSearch(query: game.title)
                    dismiss()
                } label: {
                    Label("Find on Xbox Cloud", systemImage: "cloud")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)

                if !collections.collections.isEmpty {
                    Text("Add to list")
                        .font(.title3.weight(.bold))
                    ForEach(collections.collections, id: \.id) { collection in
                        Button {
                            collections.toggle(game: game.tracked, inCollection: collection.id)
                        } label: {
                            HStack {
                                Text(collection.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: collections.contains(game.id, inCollection: collection.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(collections.contains(game.id, inCollection: collection.id) ? .green : .secondary)
                            }
                            .padding(12)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !related.isEmpty {
                    Text("Related")
                        .font(.title3.weight(.bold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(related) { item in
                                PosterCard(
                                    game: item,
                                    artworkURL: ArtworkStore.shared.url(for: item.id) ?? item.posterURL,
                                    isFavorite: session.isFavorite(item.id),
                                    onPlay: { session.playCatalogGame(item); dismiss() },
                                    onOpen: {},
                                    onFavorite: { session.toggleFavorite(item.tracked) }
                                )
                                .frame(width: 120)
                            }
                        }
                    }
                    .frame(height: 230)
                }
            }
            .padding(20)
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .background(AppBackground().ignoresSafeArea())
    }
}
