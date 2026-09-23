import SwiftUI

/// User collections — create, browse, and play lists.
struct ListsFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var store = CollectionStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @State private var newName = ""
    @State private var selected: GameCollection?
    var onOpenGame: (CatalogGame) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Lists")
                    .font(.title2.weight(.bold))

                HStack(spacing: 10) {
                    TextField("New list name", text: $newName)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button {
                        if let created = store.create(named: newName) {
                            newName = ""
                            selected = created
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glassProminent)
                }

                if store.collections.isEmpty {
                    FeatureEmptyCard(message: "Create a list to group games for later.")
                } else {
                    ForEach(store.collections, id: \.id) { collection in
                        collectionRow(collection)
                    }
                }

                if let selected {
                    collectionDetail(selected)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func collectionRow(_ collection: GameCollection) -> some View {
        Button {
            selected = collection
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(collection.gameIDs.count) games")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete list", role: .destructive) {
                store.delete(collection.id)
                if selected?.id == collection.id { selected = nil }
            }
        }
    }

    private func collectionDetail(_ collection: GameCollection) -> some View {
        let games = store.games(inCollection: collection.id, favorites: session.favorites, recents: session.recents)
        return VStack(alignment: .leading, spacing: 12) {
            Text(collection.name)
                .font(.title3.weight(.bold))
            if games.isEmpty {
                FeatureEmptyCard(message: "Open a game’s details to add it to this list.")
            } else {
                ForEach(games) { game in
                    HStack(spacing: 12) {
                        Button { onOpenGame(game) } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: artwork.url(for: game.id) ?? game.posterURL) {
                                    Color(hex: game.accent)
                                }
                                .frame(width: 44, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(game.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
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
                    .contextMenu {
                        Button("Remove from list", role: .destructive) {
                            store.toggle(game: game.tracked, inCollection: collection.id)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}
