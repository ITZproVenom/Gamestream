import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var artwork = ArtworkStore.shared
    let game: CatalogGame
    var onClose: () -> Void

    private var related: [CatalogGame] {
        GameCatalog.related(to: game)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    actions
                    meta
                    if !related.isEmpty {
                        relatedShelf
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(AnimatedBackground().ignoresSafeArea())
            .navigationTitle(game.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                        .buttonStyle(.glass)
                }
            }
        }
        .onAppear { artwork.load(game.id) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GameArtView(url: artwork.url(for: game.id), accent: game.accent, title: game.title)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(game.provider)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .lineLimit(1)
                Text(game.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(game.tagline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    session.playCatalogGame(game)
                    onClose()
                } label: {
                    Text("Play now")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("Play \(game.title)")

                Button {
                    session.toggleFavorite(game.tracked)
                } label: {
                    Image(systemName: session.isFavorite(game.id) ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 48, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(session.isFavorite(game.id) ? "Remove favorite" : "Add favorite")
            }

            Button {
                session.openCatalogGame(game)
                onClose()
            } label: {
                Text("Open on Xbox Cloud")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open \(game.title) on Xbox Cloud")
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(game.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                pill(game.genre)
                pill(game.provider)
                if session.isFavorite(game.id) { pill("Favorite") }
                if session.recents.contains(where: { $0.id == game.id }) { pill("Played") }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More \(game.genre)")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(related) { item in
                        GamePosterCard(
                            game: item,
                            artworkURL: artwork.url(for: item.id),
                            isFavorite: session.isFavorite(item.id),
                            onPlay: {
                                session.playCatalogGame(item)
                                onClose()
                            },
                            onOpen: {
                                session.openCatalogGame(item)
                                onClose()
                            },
                            onFavorite: { session.toggleFavorite(item.tracked) }
                        )
                    }
                }
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
