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

            VStack(alignment: .leading, spacing: 8) {
                Text(game.provider)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: Capsule())
                    .lineLimit(1)

                Text(game.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(game.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 10) {
                    Button {
                        SoundManager.playSuccess()
                        play()
                    } label: {
                        Text("Play")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glassProminent)

                    Button(action: favorite) {
                        Image(systemName: isFavorite() ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(isFavorite() ? "Remove from favorites" : "Add to favorites")
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    GameArtView(url: artworkURL, accent: game.accent, title: game.title)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3 / 4, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isFavorite ? .yellow : .primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(game.provider)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        SoundManager.playTap()
                        onPlay()
                    } label: {
                        Text("Play")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                }
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
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: accent).gradient)
            RemoteImage(url: url) { artFallback }
        }
        .clipped()
    }

    private var artFallback: some View {
        Text(String(title.prefix(1)))
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
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

struct HubChipStyle: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected {
            content
                .frame(minHeight: 44)
                .buttonStyle(.glassProminent)
        } else {
            content
                .frame(minHeight: 44)
                .buttonStyle(.glass)
        }
    }
}
