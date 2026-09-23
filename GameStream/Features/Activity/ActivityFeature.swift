import SwiftUI

/// Weekly and all-time play activity rebuilt for Features.
struct ActivityFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var activity = PlayActivityStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    var onOpenGame: (CatalogGame) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Activity")
                .font(.title2.weight(.bold))

            FeatureSectionCard("This week") {
                Text(PlayActivityStore.format(activity.weekTotal))
                    .font(.title.weight(.bold))
                if let live = activity.activeTitle {
                    Text("Live · \(live)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            FeatureSectionCard("All time") {
                Text(PlayActivityStore.format(activity.allTimeTotal))
                    .font(.title3.weight(.semibold))
            }

            if activity.rankedThisWeek.isEmpty {
                FeatureEmptyCard(message: "Stream a game to start tracking play time.")
            } else {
                Text("Top this week")
                    .font(.title3.weight(.bold))
                ForEach(activity.rankedThisWeek.prefix(12)) { stat in
                    let game = GameCatalog.catalog(from: TrackedGame(
                        id: stat.id,
                        slug: stat.slug,
                        title: stat.title,
                        lastSeen: stat.lastPlayed,
                        isFavorite: session.isFavorite(stat.id)
                    ))
                    HStack(spacing: 12) {
                        Button { onOpenGame(game) } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: artwork.url(for: stat.id) ?? game.posterURL) {
                                    Color(hex: game.accent)
                                }
                                .frame(width: 44, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stat.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(PlayActivityStore.format(stat.weekSeconds)) · \(stat.sessionCount) sessions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        Button { session.playCatalogGame(game) } label: {
                            Text("Play")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .padding(10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}
