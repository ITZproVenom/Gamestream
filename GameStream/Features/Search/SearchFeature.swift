import SwiftUI

struct SearchFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var catalogLive = CatalogLiveStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @State private var query: String = ""
    @FocusState private var focused: Bool
    var onOpenGame: (CatalogGame) -> Void

    private var results: [CatalogGame] {
        _ = catalogLive.revision
        return GameCatalog.matches(query)
    }

    private var recentSearches: [String] { SessionStore.recentSearches }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search games", text: $query)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runCloudIfNeeded() }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            session.openCloudSearch(query: query)
                        } label: {
                            Label("Search Xbox Cloud", systemImage: "cloud.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.glassProminent)

                        Text(results.isEmpty ? "No local matches" : "Results")
                            .font(.title3.weight(.bold))

                        if results.isEmpty {
                            FeatureEmptyCard(message: "No local titles match. Try Xbox Cloud search.")
                        } else {
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(results.prefix(40)) { game in
                                    PosterCard(
                                        game: game,
                                        artworkURL: artwork.url(for: game.id) ?? game.posterURL,
                                        isFavorite: session.isFavorite(game.id),
                                        onPlay: { session.playCatalogGame(game) },
                                        onOpen: { onOpenGame(game) },
                                        onFavorite: { session.toggleFavorite(game.tracked) }
                                    )
                                }
                            }
                        }
                    } else {
                        if !recentSearches.isEmpty {
                            HStack {
                                Text("Recent searches")
                                    .font(.title3.weight(.bold))
                                Spacer()
                                Button("Clear") {
                                    SessionStore.clearRecentSearches()
                                    session.objectWillChange.send()
                                }
                                .font(.caption.weight(.semibold))
                            }
                            ForEach(recentSearches, id: \.self) { term in
                                Button {
                                    query = term
                                    focused = true
                                } label: {
                                    HStack {
                                        Image(systemName: "clock")
                                            .foregroundStyle(.secondary)
                                        Text(term)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                        Spacer()
                                    }
                                    .padding(12)
                                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Browse")
                            .font(.title3.weight(.bold))
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(Array(GameCatalog.sortedBrowse.prefix(12))) { game in
                                PosterCard(
                                    game: game,
                                    artworkURL: artwork.url(for: game.id) ?? game.posterURL,
                                    isFavorite: session.isFavorite(game.id),
                                    onPlay: { session.playCatalogGame(game) },
                                    onOpen: { onOpenGame(game) },
                                    onFavorite: { session.toggleFavorite(game.tracked) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 88)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            if query.isEmpty { query = session.searchDraft }
            artwork.prefetch(Array(GameCatalog.sortedBrowse.prefix(24)).map(\.id))
        }
        .onChange(of: query) { _, value in
            session.updateSearchDraft(value)
        }
    }

    private func runCloudIfNeeded() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.openCloudSearch(query: trimmed)
    }
}
