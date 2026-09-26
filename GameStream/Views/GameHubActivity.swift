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

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(week)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 14) {
                if let top {
                    let game = GameCatalog.catalog(from: TrackedGame(
                        id: top.id,
                        slug: top.slug,
                        title: top.title,
                        lastSeen: top.lastPlayed,
                        isFavorite: session.isFavorite(top.id)
                    ))
                    Button { detailGame = game } label: {
                        GameArtView(url: artwork.url(for: game.id), accent: game.accent, title: game.title)
                            .frame(width: 56, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(game.title) details")

                    VStack(alignment: .leading, spacing: 5) {
                        Text(top.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("Most played · \(PlayActivityStore.format(top.weekSeconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
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
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Open activity")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct GameHubActivitySection: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var activity = PlayActivityStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @Binding var detailGame: CatalogGame?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activity")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(PlayActivityStore.format(activity.weekTotal))
                    .font(.subheadline.weight(.semibold))
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
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ForEach(activity.rankedThisWeek) { stat in
                    let game = GameCatalog.catalog(from: TrackedGame(
                        id: stat.id,
                        slug: stat.slug,
                        title: stat.title,
                        lastSeen: stat.lastPlayed,
                        isFavorite: session.isFavorite(stat.id)
                    ))
                    HStack(spacing: 14) {
                        Button { detailGame = game } label: {
                            GameArtView(url: artwork.url(for: game.id), accent: game.accent, title: game.title)
                                .frame(width: 56, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 5) {
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
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Play \(stat.title)")
                    }
                    .padding(14)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }
}
