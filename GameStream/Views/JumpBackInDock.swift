import SwiftUI

/// Persistent Jump Back In control used on GameHub and Search.
struct JumpBackInDock: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var artwork = ArtworkStore.shared
    @ObservedObject private var activity = PlayActivityStore.shared

    var body: some View {
        if let game = session.continueGame {
            let catalog = GameCatalog.catalog(from: game)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(activity.activeTitle == game.title ? "Streaming now" : "Jump back in")
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    if activity.activeTitle == game.title {
                        Text(PlayActivityStore.format(activity.liveSeconds))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 14) {
                    GameArtView(url: artwork.url(for: game.id), accent: catalog.accent, title: game.title)
                        .frame(width: 64, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        // Keep the title flexible so the action controls retain their tap target widths.
                        Text(game.title)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(GameCatalog.relativePlayLabel(for: game.lastSeen))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        HStack(spacing: 10) {
                            Button {
                                _ = session.resumeLastStream()
                            } label: {
                                Text("Resume")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.glassProminent)
                            .accessibilityLabel("Resume \(game.title)")

                            Button {
                                session.openGame(game)
                            } label: {
                                Text("Details")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Open details for \(game.title)")
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}
