import SwiftUI

struct GameHubActivityBanner: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var activity = PlayActivityStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @Binding var detailGame: CatalogGame?
    var openActivity: () -> Void

    var body: some View {
        let week = PlayActivityStore.format(activity.weekTotal)
        let top = activity.mostPlayedThisWeek
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(week)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                if let top {
                    let game = GameCatalog.catalog(from: TrackedGame(id: top.id, slug: top.slug, title: top.title, lastSeen: top.lastPlayed, isFavorite: session.isFavorite(top.id)))
                    Button { detailGame = game } label: {
                        GameArtView(url: artwork.url(for: game.id), accent: game.accent, title: game.title)
                            .frame(width: 48, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(game.title) details")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(top.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("Most played · \(PlayActivityStore.format(top.weekSeconds + (activity.activeTitle == top.title ? activity.liveSeconds : 0)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No stream time yet")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("Launch a title and GameStream will track this week’s play time on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button(action: openActivity) {
                    Text("Activity")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Open activity")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct GameHubActivitySection: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var activity = PlayActivityStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @Binding var detailGame: CatalogGame?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(PlayActivityStore.format(activity.weekTotal))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("Play time is measured on this device while a cloud stream is active.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if activity.rankedThisWeek.isEmpty {
                Text("Stream a game for at least 20 seconds and it will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(activity.rankedThisWeek) { stat in
                    let game = GameCatalog.catalog(from: TrackedGame(id: stat.id, slug: stat.slug, title: stat.title, lastSeen: stat.lastPlayed, isFavorite: session.isFavorite(stat.id)))
                    HStack(spacing: 12) {
                        Button { detailGame = game } label: {
                            GameArtView(url: artwork.url(for: game.id), accent: game.accent, title: game.title)
                                .frame(width: 48, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stat.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("\(PlayActivityStore.format(stat.weekSeconds)) this week · \(stat.sessionCount) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                        Button { session.playCatalogGame(game) } label: {
                            Text("Play")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Play \(stat.title)")
                    }
                    .padding(12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}
