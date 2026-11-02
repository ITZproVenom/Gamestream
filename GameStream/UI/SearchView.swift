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
            }
        } else {
            switch liveSearchStatus {
            case "loading", "idle":
                LoadingNotice()
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
        submittedSearchURL = url
    }

    private func receiveXboxResults(_ sourceURL: URL, _ games: [Game],
                                   _ status: String, _ message: String) {
        guard let returnedQuery = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value,
              returnedQuery.caseInsensitiveCompare(submittedSearchQuery) == .orderedSame else { return }
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
                            query = term
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.tint)
                                Text(term).font(.subheadline)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        if term != history.terms.last { Divider().opacity(0.4) }
                    }
                }
                .padding(.horizontal, 16)
                .glassEffect(.regular, in: Theme.cardShape)
                .padding(.horizontal, Theme.pageInset)
            }
        }

        if !catalog.genres.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Browse by genre")
                    .padding(.horizontal, Theme.pageInset)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(catalog.genres, id: \.self) { name in
                        Button {
                            query = name
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
                        .glassEffect(.regular.interactive(), in: Theme.tileShape)
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
