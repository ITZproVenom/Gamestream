import SwiftUI

struct SearchHubView: View {
    @EnvironmentObject var session: SessionStore
    @FocusState private var searchFocused: Bool
    @State private var recent: [String] = SessionStore.recentSearches
    @State private var pinned: [String] = SearchHistory.pinned
    @State private var detailGame: CatalogGame?
    @ObservedObject private var artwork = ArtworkStore.shared

    /// Set by RootView. The view stays mounted (for snappy tab switching) and
    /// uses this to re-sync cached lists only when it becomes the visible tab.
    var isActive: Bool = true

    private let popularTitles = ["Fortnite", "Minecraft", "Call of Duty", "Forza Horizon", "Roblox", "Sea of Thieves"]

    var body: some View {
        HubPage {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Find your next game")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            searchField

            if session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !pinned.isEmpty { queryList(title: "Pinned searches", items: pinned, pinnedStyle: true) }
                genreChips
                popularSection
                if !recent.isEmpty { queryList(title: "Recent searches", items: recent, pinnedStyle: false) }
                if !session.favorites.isEmpty {
                    libraryShelf(title: "Favorites", games: session.favorites, star: true)
                }
            } else {
                resultsSection
            }
        }
        .onAppear { reload() }
        .onChange(of: isActive) { _, active in
            if active { reload() }
        }
        .sheet(item: $detailGame) { game in
            GameDetailView(game: game) { detailGame = nil }
                .environmentObject(session)
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search games", text: Binding(
                get: { session.searchDraft },
                set: { session.updateSearchDraft($0) }
            ))
            .focused($searchFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 17, weight: .medium))
            .submitLabel(.search)
            .onSubmit { performSearch() }
            if !session.searchDraft.isEmpty {
                Button { session.updateSearchDraft("") } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var genreChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse genres").font(.title3.weight(.semibold)).lineLimit(1)
            HubCarousel(spacing: 8) {
                ForEach(GameCatalog.genreNames, id: \.self) { name in
                    Button { session.updateSearchDraft(name) } label: {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Search \(name)")
                }
            }
        }
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Popular on Cloud").font(.title3.weight(.semibold)).lineLimit(1)
            HubCarousel(spacing: 8) {
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

    private func queryList(title: String, items: [String], pinnedStyle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
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
                            Image(systemName: pinnedStyle ? "pin.fill" : "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            Text(item)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Image(systemName: "arrow.up.left").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.glass)
                    Button {
                        SearchHistory.togglePin(item)
                        reload()
                    } label: {
                        Image(systemName: SearchHistory.isPinned(item) ? "pin.fill" : "pin")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 42, height: 52)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(SearchHistory.isPinned(item) ? "Unpin \(item)" : "Pin \(item)")
                }
            }
        }
    }

    private func libraryShelf(title: String, games: [TrackedGame], star: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold)).lineLimit(1)
            ForEach(games.prefix(6)) { game in
                Button { session.openGame(game) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: star ? "star.fill" : "clock.fill").foregroundStyle(.secondary)
                        Text(game.title).font(.body.weight(.medium)).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    SearchHistory.togglePin(session.searchDraft)
                    reload()
                } label: {
                    Image(systemName: SearchHistory.isPinned(session.searchDraft) ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(SearchHistory.isPinned(session.searchDraft) ? "Unpin search" : "Pin search")
                Button { performSearch() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                        Text("Search Xbox Cloud Gaming")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }
                .buttonStyle(.glassProminent)
            }

            let catalogHits = GameCatalog.matches(session.searchDraft)
            if catalogHits.isEmpty {
                Text("No titles in the local catalog match this search. Search the full Xbox Cloud library instead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("In GameHub").font(.title3.weight(.semibold)).lineLimit(1)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(catalogHits.prefix(8)) { game in
                        GamePosterCard(
                            game: game,
                            artworkURL: artwork.url(for: game.id),
                            isFavorite: session.isFavorite(game.id),
                            onPlay: { session.playCatalogGame(game) },
                            onOpen: { detailGame = game },
                            onFavorite: { session.toggleFavorite(game.tracked) }
                        )
                        .frame(maxWidth: .infinity)
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
        session.openSearch(query: query)
    }
}
