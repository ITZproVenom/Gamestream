import SwiftUI

struct ContinuePlayingCard: View {
    @EnvironmentObject var session: SessionStore
    let game: TrackedGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue playing")
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 12) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        session.playGame(game)
                    } label: {
                        Text("Play now")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Play \(game.title)")

                    Button {
                        session.openGame(game)
                    } label: {
                        Text("Details")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Open details for \(game.title)")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct TrackedGameShelf: View {
    @EnvironmentObject var session: SessionStore
    let title: String
    let games: [TrackedGame]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            ForEach(games) { game in
                HStack(spacing: 8) {
                    Button {
                        session.openGame(game)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: title == "Favorites" ? "star.fill" : "clock.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text("Details")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)

                    Button {
                        session.playGame(game)
                    } label: {
                        Text("Play")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Play \(game.title)")

                    Button {
                        session.toggleFavorite(game)
                    } label: {
                        Image(systemName: session.isFavorite(game.id) ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 42, height: 52)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(session.isFavorite(game.id) ? "Remove favorite" : "Add favorite")
                }
            }
        }
    }
}
