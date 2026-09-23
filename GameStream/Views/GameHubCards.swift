import SwiftUI

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
            }
            .buttonStyle(.plain)

            LinearGradient(
                colors: [.clear, .black.opacity(0.45), .black.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text(game.provider)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .lineLimit(1)

                Text(game.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(game.tagline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 8) {
                    Button {
                        SoundManager.playSuccess()
                        play()
                    } label: {
                        Text("Play")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)

                    Button(action: favorite) {
                        Image(systemName: isFavorite() ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
