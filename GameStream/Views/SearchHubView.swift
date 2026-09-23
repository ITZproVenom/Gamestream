import SwiftUI

/// New Search tab. Local catalog results + hand-off to existing Xbox Cloud search WebView.
struct SearchHubView: View {
    @EnvironmentObject var session: SessionStore
    @FocusState private var searchFocused: Bool
    @State private var recent: [String] = SessionStore.recentSearches
    @State private var pinned: [String] = SearchHistory.pinned
    @State private var detailGame: CatalogGame?
    @ObservedObject private var artwork = ArtworkStore.shared

    var isActive: Bool = true

    private let popularTitles = ["Fortnite", "Minecraft", "Call of Duty", "Forza Horizon", "Roblox", "Sea of Thieves"]

    var body: some View {
        HubPage {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Local catalog or full Xbox Cloud")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            searchField

            if session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !pinned.isEmpty { queryList(title: "Pinned", items: pinned, pinnedStyle: true) }
                genreChips
                popularSection
                if !recent.isEmpty { queryList(title: "Recent", items: recent, pinnedStyle: false) }
                if !session.favorites.isEmpty {
                    libraryShelf(title: "Favorites", games: session.favorites)
                }
            } else {
                resultsSection
            }
        }
        .onAppear { reload() }
        .onChange(of: isActive) { _, active in if active { reload() } }
        .sheet(item: $detailGame) { game in
            GameDetailView(game: game) { detailGame = nil }
                .environmentObject(session)
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search games", text: Binding(
                get: { session.searchDraft },
                set: { session.updateSearchDraft($0) }
            ))
            .focused($searchFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit { performSearch() }
            if !session.searchDraft.isEmpty {
                Button { session.updateSearchDraft("") } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var genreChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Genres").font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GameCatalog.genreNames, id: \.self) { name in
                        Button { session.updateSearchDraft(name) } label: {
                            Text(name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Popular").font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popularTitles, id: \.self) { title in
                        Button {
                            session.updateSearchDraft(title)
                            performSearch()
                        } label: {
                            Text(title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private func queryList(title: String, items: [String], pinnedStyle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.weight(.bold))
                Spacer()
                if !pinnedStyle {
                    Button("Clear") {
                        SessionStore.clearRecentSearches()
                        reload()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
            ForEach(items, id: \.self) { item in
                HStack(spacing: 8) {
                    Button {
                        session.updateSearchDraft(item)
                        performSearch()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pinnedStyle ? "pin.fill" : "clock")
                                .foregroundStyle(.secondary)
                            Text(item).font(.body.weight(.medium)).lineLimit(1)
                            Spacer()
                        }
                        .padding(14)
                    }
                    .buttonStyle(.glass)
                    Button {
                        SearchHistory.togglePin(item)
                        reload()
                    } label: {
                        Image(systemName: SearchHistory.isPinned(item) ? "pin.fill" : "pin")
                            .frame(width: 44, height: 48)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private func libraryShelf(title: String, games: [TrackedGame]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.bold))
            ForEach(games.prefix(6)) { game in
                let catalog = GameCatalog.catalog(from: game)
                Button { detailGame = catalog } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill").foregroundStyle(.secondary)
                        Text(catalog.title).font(.body.weight(.medium)).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { performSearch() } label: {
                Label("Search Xbox Cloud", systemImage: "cloud.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)

            let hits = GameCatalog.matches(session.searchDraft)
            if hits.isEmpty {
                Text("No local matches. Use Xbox Cloud search above for the full library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text("In GameHub").font(.title3.weight(.bold))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(hits.prefix(12)) { game in
                        GamePosterCard(
                            game: game,
                            artworkURL: artwork.url(for: game.id),
                            isFavorite: session.isFavorite(game.id),
                            onPlay: { session.playCatalogGame(game) },
                            onOpen: { detailGame = game },
                            onFavorite: { session.toggleFavorite(game.tracked) }
                        )
                    }
                }
            }
        }
    }

    private func reload() {
        recent = SessionStore.recentSearches
        pinned = SearchHistory.pinned
    }

    private func performSearch() {
        let query = session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchFocused = false
        SessionStore.rememberSearch(query)
        reload()
        // LOCKED PATH: openCloudSearch → existing streaming WebView
        session.openSearch(query: query)
    }
}
