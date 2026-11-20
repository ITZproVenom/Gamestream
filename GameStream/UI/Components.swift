import SwiftUI
import UIKit

/// Artwork that loads through the shared cache and never blocks the interface.
struct GameArtwork: View {
    let url: URL?
    var cornerRadius: CGFloat = Theme.tileRadius

    @State private var image: UIImage?

    var body: some View {
        // The artwork is an *overlay* on the placeholder, never a sibling in a
        // stack. `scaledToFill` reports the filled size as its own, so an
        // image in a stack makes the stack as wide as the image — 533pt for a
        // 16:9 hero 300pt tall. `clipped()` hides the overflow but does not
        // undo it, so the whole page inherited that width and sat off the
        // left edge with the poster and the stat cards sliced. An overlay
        // cannot change its host's size, which ends that class of bug.
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                        // A placeholder is a picture of nothing: a screen
                        // reader should say the title, not "game controller
                        // fill", before it.
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await PosterCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
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
    var showsPlayButton = true
    let play: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @ScaledMetric(relativeTo: .subheadline) private var titleSlotHeight = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                NavigationLink(value: game) {
                    GameArtwork(url: game.posterURL)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            if library.isFavorite(game) {
                                Image(systemName: "heart.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.pink)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular, in: Circle())
                                    .padding(Theme.badgeInset)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(game.title)
                // A heart in the corner is the only sign that a game is a
                // favourite, and a screen reader never says it.
                .accessibilityValue(library.isFavorite(game) ? "Favourite" : "")

                if showsPlayButton {
                    Button(action: play) {
                        Image(systemName: "play.fill")
                            .font(.footnote.weight(.bold))
                            // The glyph is small, but the target is not:
                            // the touch area around it is the full
                            // forty-four points.
                            .frame(width: 36, height: 36)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .padding(Theme.badgeInset)
                    .accessibilityLabel("Play \(game.title)")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(height: titleSlotHeight, alignment: .topLeading)
                Text(game.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.cardContentInset)
        .modifier(CardSurfaceModifier(shape: Theme.tileShape))
    }
}

/// The smaller card used in horizontal rows.
struct GameCard: View {
    let game: Game
    var width: CGFloat = 128
    var caption: String?

    @ScaledMetric(relativeTo: .subheadline) private var titleSlotHeight = 40
    @ScaledMetric(relativeTo: .caption) private var captionSlotHeight = 18

    var body: some View {
        NavigationLink(value: game) {
            VStack(alignment: .leading, spacing: 8) {
                GameArtwork(url: game.posterURL)
                    .aspectRatio(3 / 4, contentMode: .fit)
                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: titleSlotHeight, alignment: .topLeading)
                // A blank caption still occupies its row. This keeps every
                // card bottom and every following shelf on the same guide.
                Text(caption ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: captionSlotHeight, alignment: .topLeading)
                    .accessibilityHidden(caption == nil)
            }
            .padding(Theme.cardContentInset)
            // The caller's width is the complete card width, not just the
            // content width before padding is added.
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .modifier(CardSurfaceModifier(shape: Theme.tileShape))
        }
        .buttonStyle(.plain)
    }
}

struct GameRow: View {
    let game: Game
    var caption: String?

    var body: some View {
        HStack(spacing: 13) {
            GameArtwork(url: game.posterURL, cornerRadius: 10)
                .frame(width: 46, height: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(caption ?? game.genre)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A horizontally scrolling shelf of cards, with snapping.
struct GameShelf: View {
    let games: [Game]
    var width: CGFloat = 128
    var caption: (Game) -> String? = { _ in nil }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Theme.shelfGutter) {
                ForEach(games) { game in
                    GameCard(game: game, width: width, caption: caption(game))
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.7)
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        // Safe-area padding preserves both the leading card guide and the
        // trailing scroll inset without changing the snapping card width.
        .safeAreaPadding(.horizontal, Theme.pageInset)
    }
}

/// One consistent way to report a failure, with a way out of it.
struct ErrorNotice: View {
    let title: String
    let message: String
    var retryTitle: String = "Try again"
    let retry: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 11) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(retryTitle, action: retry)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LoadingNotice: View {
    var title = "Loading the Xbox catalog…"

    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .accessibilityLabel(title)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

/// Shown where a list would otherwise be blank, with the action that fills it.
struct EmptyNotice: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
    }
}

enum Format {
    /// "1h 24m", "12m", "<1m" — short enough for a caption.
    static func duration(_ seconds: TimeInterval) -> String {
        // A non-finite value would trap on conversion to Int, so a bad
        // reading is reported as a short session rather than a crash.
        guard seconds.isFinite else { return "<1m" }
        let minutes = Int(min(seconds, 1e9) / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// "1:04:12" — for a timer that is ticking in front of the user.
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(Int(min(seconds, 1e9).rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
