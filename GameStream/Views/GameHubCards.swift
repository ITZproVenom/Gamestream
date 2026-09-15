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
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                Text(game.provider).font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.ultraThinMaterial, in: Capsule()).lineLimit(1)
                Text(game.title).font(.title2.weight(.bold)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
                Text(game.tagline).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                HStack(spacing: 8) {
                    Button(action: { SoundManager.playSuccess(); play() }) { Text("Play").font(.subheadline.weight(.semibold)).lineLimit(1).padding(.horizontal, 16).padding(.vertical, 8) }.buttonStyle(.glassProminent)
                    Button(action: favorite) { Image(systemName: isFavorite() ? "star.fill" : "star").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 34) }.buttonStyle(.glass)
                }
            }
            .padding(16)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    GameArtView(url: artworkURL, accent: game.accent, title: game.title)
                        .frame(maxWidth: .infinity)
                        .frame(height: 176)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain)
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star").font(.system(size: 11, weight: .bold)).padding(6).background(.ultraThinMaterial, in: Circle())
                }.buttonStyle(.plain).padding(8)
            }
            Text(game.title).font(.caption.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(game.provider).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(action: { SoundManager.playTap(); onPlay() }) { Text("Play").font(.caption2.weight(.semibold)).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 5) }.buttonStyle(.glassProminent)
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
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(hex: accent).gradient)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: artFallback
                    }
                }
            } else { artFallback }
        }.clipped()
    }
    private var artFallback: some View {
        Text(String(title.prefix(1))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
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
