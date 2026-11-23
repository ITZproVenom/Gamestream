import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var stream: StreamCoordinator
    @StateObject private var history = SearchHistory.shared

    @State private var query = ""
    @State private var submittedSearchURL: URL?
    @State private var submittedSearchQuery = ""
    @State private var liveGames: [Game] = []
    @State private var liveSearchStatus = "idle"
    @State private var liveSearchMessage = ""
    @State private var searchReloadToken = 0
    /// The genre being browsed, when the player picked one from the grid.
    @State private var genreFilter: String?
    /// Game counts by genre, worked out when the catalogue changes rather
    /// than once for every genre whenever the screen is drawn.
    @State private var genreCounts: [String: Int] = [:]
    @StateObject private var navigator = RootView.Navigator.shared

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 190), spacing: 16)]

    var body: some View {
        ZStack {
            if let submittedSearchURL {
                XboxWebView(role: .searchResults,
                            url: submittedSearchURL,
                            reloadToken: searchReloadToken,
                            onSearchResults: receiveXboxResults)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if query.isEmpty {
                            idleContent
                        } else {
                            liveSearchContent
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 36)
                    .containerRelativeFrame(.horizontal)
                }
                .refreshable {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        await catalog.refresh()
                    } else {
                        openXboxResults()
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .background { AuroraBackground() }
                .navigationTitle("Search")
                .searchable(text: $query, prompt: "Games on Xbox Cloud Gaming")
                .searchToolbarBehavior(.minimize)
                .onSubmit(of: .search) { openXboxResults() }
                .onChange(of: navigator.searchSeed) { _, seed in
                    guard let seed, !seed.isEmpty else { return }
                    query = seed
                    navigator.searchSeed = nil
                    openXboxResults(for: seed)
                }
                .onChange(of: catalog.games, initial: true) { _, games in
                    var counts: [String: Int] = [:]
                    for game in games {
                        counts[game.genre, default: 0] += 1
                    }
                    genreCounts = counts
                }
                .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            }
        }
    }

    @ViewBuilder
    private var liveSearchContent: some View {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            idleContent
        } else if submittedSearchQuery.caseInsensitiveCompare(clean) != .orderedSame {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Xbox Cloud Gaming", subtitle: "Search Xbox's live catalog")
                    .padding(.horizontal, Theme.pageInset)
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Find current cloud-playable games directly from Xbox, including titles outside the Game Pass catalog feed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button { openXboxResults() } label: {
                            Label("Search Xbox for ‘\(clean)’", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                    }
                }
                .padding(.horizontal, Theme.pageInset)

                // A title the catalogue has not caught up with can still be
                // started, if its product id is known.
                if let direct = directTarget(for: clean) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Start it by its product id")
                                .font(.subheadline.weight(.semibold))
                            Text(catalog.games.contains { $0.matches(id: direct.id) }
                                 ? "It is in the catalogue, but it can also be started directly from here."
                                 : "This title is not in the app's catalogue, but it can be asked for directly. Whether the cloud streams it is Microsoft's decision.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                stream.play(direct)
                            } label: {
                                Label("Play \(direct.title)", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal, Theme.pageInset)
                }
            }
        } else {
            switch liveSearchStatus {
            case "loading", "idle":
                LoadingNotice(title: "Asking Xbox for its live catalog…")
            case "results" where !liveGames.isEmpty:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Xbox results",
                                  subtitle: "\(liveGames.count) live result\(liveGames.count == 1 ? "" : "s")")
                        .padding(.horizontal, Theme.pageInset)
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(liveGames) { game in
                            GameTile(game: game) { stream.play(game) }
                        }
                    }
                    .padding(.horizontal, Theme.pageInset)
                }
            case "empty":
                EmptyNotice(systemImage: "magnifyingglass",
                            title: "No Xbox results",
                            message: liveSearchMessage.isEmpty
                                ? "Xbox Cloud Gaming returned no matches for ‘\(clean)’."
                                : liveSearchMessage,
                            actionTitle: "Search again") { openXboxResults() }
            default:
                ErrorNotice(title: "Xbox search unavailable",
                            message: liveSearchMessage.isEmpty
                                ? "Xbox's live results could not be read. Check your connection and try again."
                                : liveSearchMessage) {
                    openXboxResults()
                }
                .padding(.horizontal, Theme.pageInset)
            }
        }
    }

    private func openXboxResults(for value: String? = nil) {
        let clean = (value ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        history.record(clean)
        var components = URLComponents(string: "https://www.xbox.com/play/search")
        components?.queryItems = [URLQueryItem(name: "q", value: clean)]
        guard let url = components?.url else {
            liveSearchStatus = "error"
            liveSearchMessage = "The search text could not be encoded."
            return
        }
        submittedSearchQuery = clean
        liveGames = []
        liveSearchMessage = ""
        liveSearchStatus = "loading"
        searchReloadToken &+= 1
        submittedSearchURL = url
    }

    /// The title a query names directly, when the query is a product id or
    /// an Xbox link.
    private func directTarget(for query: String) -> Game? {
        if let link = DirectLaunch.productID(inLink: query) {
            return DirectLaunch.game(forID: link.id, slug: link.slug)
        }
        if let id = DirectLaunch.productID(in: query) {
            return DirectLaunch.game(forID: id)
        }
        return nil
    }

    /// Takes the answer from the search page.
    ///
    /// The site redirects the search page to a localized path such as
    /// /en-IN/play/search, so the host and the path of the URL that comes
    /// back are not the ones that were asked for. Only the query text
    /// identifies the answer, so it is the query text that is compared.
    private func receiveXboxResults(_ sourceURL: URL, _ games: [Game],
                                   _ status: String, _ message: String) {
        // A search must be on screen for an answer to belong to it.
        guard submittedSearchURL != nil else { return }
        // When the page still carries the query text, it has to be the text
        // that was searched for. The redirect can rewrite the URL and drop
        // the query it carried, and then the answer is the one the search
        // in flight is waiting for.
        if let returnedQuery = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value {
            guard returnedQuery.caseInsensitiveCompare(submittedSearchQuery) == .orderedSame else { return }
        }
        liveGames = games
        liveSearchStatus = status
        liveSearchMessage = message
        submittedSearchURL = nil
    }

    @ViewBuilder
    private var idleContent: some View {
        if !history.terms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recent searches", actionTitle: "Clear") {
                    history.clear()
                }
                .padding(.horizontal, Theme.pageInset)

                VStack(spacing: 0) {
                    ForEach(history.terms, id: \.self) { term in
                        Button {
                            // The button says "search for this again", so it
                            // searches: it only filled the field before, and
                            // the results did not appear until something
                            // else was pressed.
                            query = term
                            openXboxResults(for: term)
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                                Text(term).font(.subheadline)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 11)
                            .accessibilityLabel("Search for \(term) again")
                        }
                        .buttonStyle(.plain)
                        if term != history.terms.last { Divider().opacity(0.4) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.small)
                .modifier(CardSurfaceModifier(shape: Theme.cardShape))
                .padding(.horizontal, Theme.pageInset)
            }
        }

        if let genre = genreFilter {
            let games = catalog.games(inGenre: genre)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: genre, actionTitle: "All genres") {
                    genreFilter = nil
                }
                .padding(.horizontal, Theme.pageInset)

                if games.isEmpty {
                    EmptyNotice(systemImage: "square.stack",
                                title: "Nothing in \(genre)",
                                message: "The catalogue has no games in this genre right now.",
                                actionTitle: "All genres") { genreFilter = nil }
                        .padding(.horizontal, Theme.pageInset)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(games) { game in
                            GameTile(game: game) { stream.play(game) }
                        }
                    }
                    .padding(.horizontal, Theme.pageInset)
                }
            }
        } else if !catalog.genres.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Browse by genre")
                    .padding(.horizontal, Theme.pageInset)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(catalog.genres, id: \.self) { name in
                        Button {
                            // The tile says how many games are in the genre,
                            // so it shows them: it asked Xbox for a search
                            // of the genre's name before.
                            genreFilter = name
                        } label: {
                            HStack {
                                Text(name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                Text("\(catalog.games(inGenre: name).count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .modifier(CardSurfaceModifier(shape: Theme.tileShape))
                    }
                }
                .padding(.horizontal, Theme.pageInset)
            }
        }

        if !library.favorites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Your favorites")
                    .padding(.horizontal, Theme.pageInset)
                GameShelf(games: Array(library.favorites.prefix(12)))
            }
        }
    }
}
