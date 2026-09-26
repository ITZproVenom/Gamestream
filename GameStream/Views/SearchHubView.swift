import SwiftUI

struct SearchHubView: View {
    @EnvironmentObject var session: SessionStore
    @FocusState private var searchFocused: Bool
    @State private var recent: [String] = SessionStore.recentSearches
    @State private var pinned: [String] = SearchHistory.pinned
    @State private var detailGame: CatalogGame?
    @ObservedObject private var artwork = ArtworkStore.shared
    @ObservedObject private var catalogLive = CatalogLiveStore.shared

    var isActive: Bool = true

    private let popularTitles = ["Fortnite", "Minecraft", "Call of Duty", "Forza Horizon", "Roblox", "Sea of Thieves"]

    var body: some View {
        HubPage(horizontalPadding: 20) {
            header
            searchField

            if session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                discoverContent
            } else {
                resultsSection
            }
        }
        .onAppear {
            let _ = catalogLive.revision
            reload()
        }
        .onChange(of: isActive) { _, active in
            if active { reload() }
        }
        .sheet(item: $detailGame) { game in
            GameDetailView(game: game) { detailGame = nil }
                .environmentObject(session)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Search")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .lineLimit(1)

            Text("Find a game, genre, or something to play next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 11) {
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
            .font(.body)
            .submitLabel(.search)
            .onSubmit { performSearch() }

            if !session.searchDraft.isEmpty {
                Button {
                    session.updateSearchDraft("")
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var discoverContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let game = session.continueGame {
                ContinuePlayingCard(game: game)
            }

            if !pinned.isEmpty {
                querySection(title: "Pinned", icon: "pin.fill", items: pinned, showsClear: false)
            }

            genreSection
            popularSection

            if !recent.isEmpty {
                querySection(title: "Recent", icon: "clock.arrow.circlepath", items: recent, showsClear: true)
            }

            if !session.favorites.isEmpty {
                favoritesSection
            }
        }
    }

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Browse by genre")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GameCatalog.genreNames, id: \.self) { name in
                        Button {
                            session.updateSearchDraft(name)
                            performSearch()
                        } label: {
                            Text(name)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Popular searches")

            VStack(spacing: 0) {
                ForEach(Array(popularTitles.enumerated()), id: \.offset) { index, title in
                    Button {
                        session.updateSearchDraft(title)
                        performSearch()
                    } label: {
                        HStack(spacing: 13) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 20)

                            Text(title)
                                .font(.body.weight(.medium))

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < popularTitles.count - 1 {
                        Divider().padding(.leading, 33)
                    }
                }
            }
        }
    }

    private func querySection(title: String, icon: String, items: [String], showsClear: Bool) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionTitle(title, icon: icon)
                Spacer()
                if showsClear {
                    Button("Clear") {
                        SessionStore.clearRecentSearches()
                        reload()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        Button {
                            session.updateSearchDraft(item)
                            performSearch()
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                Text(item)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer()

                                Image(systemName: "arrow.up.left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            SearchHistory.togglePin(item)
                            reload()
                        } label: {
                            Image(systemName: SearchHistory.isPinned(item) ? "pin.fill" : "pin")
                                .font(.caption.weight(.semibold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(SearchHistory.isPinned(item) ? "Unpin \(item)" : "Pin \(item)")
                    }
                    .padding(.vertical, 8)

                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Your favorites", icon: "star.fill")

            VStack(spacing: 0) {
                ForEach(session.favorites.prefix(6)) { game in
                    Button { session.openGame(game) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .frame(width: 22)

                            Text(game.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if game.id != session.favorites.prefix(6).last?.id {
                        Divider().padding(.leading, 34)
                    }
                }
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Results")
                        .font(.title3.weight(.bold))
                    Text(session.searchDraft)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    SearchHistory.togglePin(session.searchDraft)
                    reload()
                } label: {
                    Image(systemName: SearchHistory.isPinned(session.searchDraft) ? "pin.fill" : "pin")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(SearchHistory.isPinned(session.searchDraft) ? "Unpin search" : "Pin search")
            }

            let catalogHits = GameCatalog.matches(session.searchDraft)

            if catalogHits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing in GameHub matches this search.")
                        .font(.headline)
                    Text("Search the full Xbox Cloud Gaming catalog for more results.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                    ForEach(catalogHits.prefix(12)) { game in
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

            Button {
                performSearch()
            } label: {
                HStack {
                    Image(systemName: "cloud.fill")
                    Text("Search Xbox Cloud Gaming")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .buttonStyle(.glassProminent)
        }
    }

    private func sectionTitle(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.headline.weight(.semibold))
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
