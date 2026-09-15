import SwiftUI

/// Persistent Jump Back In control used on GameHub and Search.
struct JumpBackInDock: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var artwork = ArtworkStore.shared
    @ObservedObject private var activity = PlayActivityStore.shared

    var body: some View {
        if let game = session.continueGame {
            let catalog = GameCatalog.catalog(from: game)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(activity.activeTitle == game.title ? "Streaming now" : "Jump back in")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    if activity.activeTitle == game.title {
                        Text(PlayActivityStore.format(activity.liveSeconds))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 12) {
                    GameArtView(url: artwork.url(for: game.id), accent: catalog.accent, title: game.title)
                        .frame(width: 56, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(game.title)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(GameCatalog.relativePlayLabel(for: game.lastSeen))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Button {
                                _ = session.resumeLastStream()
                            } label: {
                                Text("Resume")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.glassProminent)
                            .accessibilityLabel("Resume \(game.title)")
                            Button {
                                session.openGame(game)
                            } label: {
                                Text("Details")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Open details for \(game.title)")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}
