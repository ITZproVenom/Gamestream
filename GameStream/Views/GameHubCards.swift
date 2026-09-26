import SwiftUI

// MARK: - Hero

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
                colors: [.clear, .black.opacity(0.5), .black.opacity(0.92)],
                startPoint: UnitPoint(x: 0.5, y: 0.25),
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
                    Button {
                        SoundManager.playSuccess()
                        play()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)

                    Button(action: favorite) {
                        Image(systemName: isFavorite() ? "star.fill" : "star")
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

// MARK: - Poster — fixed footprint so carousels never overlap

struct GamePosterCard: View {
    let game: CatalogGame
    let artworkURL: URL?
    let isFavorite: Bool
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onFavorite: () -> Void

    /// Total height is art (3:4) + title band + play button — locked.
    static let titleBand: CGFloat = 44
    static let playBand: CGFloat = 40
    static let spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isFavorite ? .yellow : .white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .layoutPriority(1)

            Text(game.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: Self.titleBand, maxHeight: Self.titleBand, alignment: .topLeading)

            Button {
                SoundManager.playTap()
                onPlay()
            } label: {
                Text("Play")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.playBand - 4)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Art

struct GameArtView: View {
    let url: URL?
    let accent: UInt32
    let title: String

    var body: some View {
        ZStack {
            Color(hex: accent)
            RemoteImage(url: url) {
                Text(String(displayLetter))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .clipped()
    }

    private var displayLetter: Character {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.first ?? "?"
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
