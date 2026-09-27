import SwiftUI
import UIKit

/// Artwork that loads through the shared cache and never blocks the interface.
struct GameArtwork: View {
    let url: URL?
    var cornerRadius: CGFloat = 14

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .tertiarySystemFill))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await PosterCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { image = loaded }
        }
    }
}

/// A poster with its title, used in every grid.
///
/// The artwork link and the play button are siblings in a `ZStack`, never
/// nested. A control placed inside another control's label does not reliably
/// receive taps, which is how a "play" button ends up opening a detail page.
struct GameTile: View {
    let game: Game
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                NavigationLink(value: game) {
                    GameArtwork(url: game.posterURL, cornerRadius: 16)
                        .aspectRatio(3 / 4, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(game.title)

                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.92), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Play \(game.title)")
            }

            Text(game.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(game.genre)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// The smaller card used in horizontal rows.
struct GameCard: View {
    let game: Game

    var body: some View {
        NavigationLink(value: game) {
            VStack(alignment: .leading, spacing: 7) {
                GameArtwork(url: game.posterURL)
                    .aspectRatio(3 / 4, contentMode: .fit)
                Text(game.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

struct GameRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            GameArtwork(url: game.posterURL, cornerRadius: 9)
                .frame(width: 46, height: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(game.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline.weight(.semibold))
            }
        }
    }
}

struct HorizontalGameRow: View {
    let games: [Game]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 13) {
                ForEach(games) { game in
                    GameCard(game: game).frame(width: 124)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

/// One consistent way to report a failure, with a way out of it.
struct ErrorNotice: View {
    let title: String
    let message: String
    var retryTitle: String = "Try again"
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(retryTitle, action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct LoadingNotice: View {
    var title = "Loading the Xbox catalog…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct Pill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

enum Format {
    /// "1h 24m", "12m", "<1m" — short enough for a caption.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
