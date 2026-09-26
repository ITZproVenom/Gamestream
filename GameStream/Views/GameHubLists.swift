import SwiftUI

struct GameHubListShelves: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var lists = CollectionStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @State private var detailGame: CatalogGame?

    var body: some View {
        Group {
            GameHubQueueShelf(detailGame: $detailGame)
            ForEach(lists.collections) { list in
                let games = lists.games(inCollection: list.id, favorites: session.favorites, recents: session.recents)
                if !games.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HubSectionHeader(title: list.name)
                        HubCarousel(spacing: 14) {
                            ForEach(games) { game in
                                GamePosterCard(
                                    game: game,
                                    artworkURL: artwork.url(for: game.id),
                                    isFavorite: session.isFavorite(game.id),
                                    onPlay: { session.playCatalogGame(game) },
                                    onOpen: { detailGame = game },
                                    onFavorite: { session.toggleFavorite(game.tracked) }
                                )
                                .containerRelativeFrame(.horizontal) { width, _ in
                                    HubMetrics.posterWidth(containerWidth: width)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $detailGame) { game in
            GameDetailView(game: game) { detailGame = nil }
                .environmentObject(session)
        }
    }
}

struct GameHubListsSection: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var lists = CollectionStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @Binding var showingLists: Bool
    @Binding var detailGame: CatalogGame?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GameHubQueueShelf(detailGame: $detailGame)

            HStack {
                Text("Your lists")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Button {
                    showingLists = true
                } label: {
                    Text("Manage")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Manage lists")
            }

            if lists.collections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No lists yet")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Create a named list from a game page, then pin titles for weekend co-op, backlog, or kids' games.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showingLists = true
                    } label: {
                        Text("Create a list")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Create a list")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ForEach(lists.collections) { list in
                    let games = lists.games(inCollection: list.id, favorites: session.favorites, recents: session.recents)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(list.name)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 8)
                            Text("\(games.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if games.isEmpty {
                            Text("Empty list — add games from a title page.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            HubCarousel(spacing: 14) {
                                ForEach(games) { game in
                                    GamePosterCard(
                                        game: game,
                                        artworkURL: artwork.url(for: game.id),
                                        isFavorite: session.isFavorite(game.id),
                                        onPlay: { session.playCatalogGame(game) },
                                        onOpen: { detailGame = game },
                                        onFavorite: { session.toggleFavorite(game.tracked) }
                                    )
                                    .containerRelativeFrame(.horizontal) { width, _ in
                                        HubMetrics.posterWidth(containerWidth: width)
                                    }
                                    .contextMenu {
                                        Button { session.playCatalogGame(game) } label: {
                                            Label("Play now", systemImage: "play.fill")
                                        }
                                        Button {
                                            lists.toggle(game: game.tracked, inCollection: list.id)
                                        } label: {
                                            Label("Remove from \(list.name)", systemImage: "minus.circle")
                                        }
                                        Button { session.toggleQueue(game.tracked) } label: {
                                            Label(
                                                session.isQueued(game.id) ? "Remove from Up Next" : "Add to Up Next",
                                                systemImage: "text.badge.plus"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }


    }
}
