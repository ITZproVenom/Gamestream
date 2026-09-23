import SwiftUI

struct HeroCard: View {
    let game: CatalogGame
    let artworkURL: URL?
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onFavorite: () -> Void
    let isFavorite: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: onOpen) {
                RemoteImage(url: artworkURL) {
                    Color(hex: game.accent)
                }
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .buttonStyle(.plain)

            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.92)],
                startPoint: UnitPoint(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                Text(game.provider)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: Capsule())
                Text(game.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(game.tagline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    Button(action: onFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Poster + fixed title band + Play. Art is constrained so it never bleeds into the next grid column.
struct PosterCard: View {
    let game: CatalogGame
    let artworkURL: URL?
    let isFavorite: Bool
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardStackSpacing) {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    // Fit box first, then fill+clip inside — prevents column overflow on narrow phones
                    Color.clear
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay {
                            RemoteImage(url: artworkURL) {
                                Color(hex: game.accent)
                            }
                            .scaledToFill()
                        }
                        .clipped()
                }
                .buttonStyle(.plain)

                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isFavorite ? .yellow : .white)
                        .padding(8)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(game.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.titleBand, maxHeight: LayoutMetrics.titleBand, alignment: .topLeading)

            Button(action: onPlay) {
                Text("Play")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: LayoutMetrics.playBand)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
