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

                HStack(alignment: .top, spacing: 14) {
                    GameArtView(url: artwork.url(for: game.id), accent: catalog.accent, title: game.title)
                        .frame(width: 64, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayTitle(for: game))
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
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
                                    .minimumScaleFactor(0.85)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.glassProminent)
                            .layoutPriority(1)
                            .accessibilityLabel("Resume \(displayTitle(for: game))")

                            Button {
                                session.openGame(game)
                            } label: {
                                Text("Details")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Open details for \(displayTitle(for: game))")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    /// Prefer short catalog title over long marketing / page titles.
    private func displayTitle(for game: TrackedGame) -> String {
        if let catalog = GameCatalog.game(id: game.id), !catalog.title.isEmpty {
            return catalog.title
        }
        // Strip leading junk like "D " from broken page-title parses.
        var t = game.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 2, t[t.startIndex].isLetter, t[t.index(after: t.startIndex)] == " ",
           t.uppercased().hasPrefix("D ") || t.uppercased().hasPrefix("A ") {
            let rest = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if rest.count > 3 { t = rest }
        }
        return t
    }
}
