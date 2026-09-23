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
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
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
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)

                Text(game.tagline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 10) {
                    Button {
                        SoundManager.playSuccess()
                        play()
                    } label: {
                        Text("Play")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .frame(minWidth: 72)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glassProminent)

                    Button(action: favorite) {
                        Image(systemName: isFavorite() ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Poster tile: art + title + full-width Play. No overlapping chrome.
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
                        .aspectRatio(3 / 4, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
                .buttonStyle(.plain)

                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isFavorite ? .yellow : .white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(game.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)

            Button {
                SoundManager.playTap()
                onPlay()
            } label: {
                Text("Play")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}
