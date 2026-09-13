import SwiftUI

struct ListsBrowserView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var lists = CollectionStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @State private var newName = ""
    var onPlay: (CatalogGame) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        TextField("New list name", text: $newName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit { create() }
                        Button("Add") { create() }
                            .buttonStyle(.glassProminent)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if lists.collections.isEmpty {
                        Text("Create a list, then add games from a title page or the hub.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(lists.collections) { list in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(list.name)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 8)
                                Text("\(list.gameIDs.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    lists.delete(list.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.glass)
                                .accessibilityLabel("Delete \(list.name)")
                            }

                            let games = lists.games(inCollection: list.id, favorites: session.favorites, recents: session.recents)
                            if games.isEmpty {
                                Text("Empty list")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(games) { game in
                                            GamePosterCard(
                                                game: game,
                                                artworkURL: artwork.url(for: game.id),
                                                isFavorite: session.isFavorite(game.id),
                                                onPlay: { onPlay(game) },
                                                onOpen: { onPlay(game) },
                                                onFavorite: { session.toggleFavorite(game.tracked) }
                                            )
                                            .frame(width: 132)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(AnimatedBackground().ignoresSafeArea())
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func create() {
        _ = lists.create(named: newName)
        newName = ""
    }
}
