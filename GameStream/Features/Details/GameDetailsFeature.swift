import SwiftUI

struct GameDetailsFeature: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let game: CatalogGame

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
                Text(game.genre)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())

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
