import SwiftUI

struct LibraryView: View {
    enum Filter: Hashable {
        case all, favorites, recent, upNext, genre(String)

        var title: String {
            switch self {
            case .all: return "All games"
            case .favorites: return "Favorites"
            case .recent: return "Recently played"
            case .upNext: return "Up next"
            case .genre(let name): return name
            }
        }
    }

    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var stream: StreamCoordinator

    @State private var filter: Filter = .all
    @State private var showingLists = false

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 14)]

    private var games: [Game] {
        switch filter {
        case .all: return catalog.games
        case .favorites: return library.favorites
        case .recent: return library.recents
        case .upNext: return library.queue
        case .genre(let name): return catalog.games(inGenre: name)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(games) { game in
                                GameTile(game: game) { stream.play(game) }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(filter.title)
            .refreshable { await catalog.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            Text("All games").tag(Filter.all)
                            Text("Favorites").tag(Filter.favorites)
                            Text("Recently played").tag(Filter.recent)
                            Text("Up next").tag(Filter.upNext)
                        }
                        if !catalog.genres.isEmpty {
                            Menu("Genres") {
                                ForEach(catalog.genres, id: \.self) { genre in
                                    Button(genre) { filter = .genre(genre) }
                                }
                            }
                        }
                        Divider()
                        Button("Manage lists") { showingLists = true }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter the library")
                }
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .sheet(isPresented: $showingLists) { ListsView() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if catalog.isLoading {
            LoadingNotice()
        } else if let error = catalog.errorMessage, filter == .all {
            ScrollView {
                ErrorNotice(title: "Catalog unavailable", message: error) {
                    Task { await catalog.refresh() }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "square.grid.2x2",
                description: Text(emptyMessage)
            )
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .favorites: return "No favorites yet"
        case .recent: return "Nothing played yet"
        case .upNext: return "Up next is empty"
        default: return "No games"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .favorites: return "Star a game on its page to keep it here."
        case .recent: return "Games you play will appear here."
        case .upNext: return "Queue a game from its page to line it up."
        default: return "Pull down to load the Xbox catalog again."
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var stream: StreamCoordinator

    @State private var query = ""
    @State private var recents: [String] = SearchHistory.load()

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 14)]

    private var results: [Game] {
        catalog.search(query)
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    startScreen
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(results) { game in
                                GameTile(game: game) { stream.play(game) }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Games, genres, descriptions")
            .onSubmit(of: .search) {
                recents = SearchHistory.remember(query)
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
        }
    }

    private var startScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !recents.isEmpty {
                    HStack {
                        SectionHeader(title: "Recent searches")
                        Button("Clear") {
                            recents = SearchHistory.clear()
                        }
                        .font(.footnote)
                    }
                    ForEach(recents, id: \.self) { term in
                        Button {
                            query = term
                        } label: {
                            Label(term, systemImage: "clock")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !catalog.genres.isEmpty {
                    SectionHeader(title: "Browse by genre")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        ForEach(catalog.genres, id: \.self) { genre in
                            Button {
                                query = genre
                            } label: {
                                Text(genre)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

/// Recent search terms. Kept out of the view so the list can be updated as
/// state rather than re-read from storage during a redraw, which is why the
/// 1.x version never refreshed until something else happened to redraw it.
enum SearchHistory {
    private static let key = "search.recents.v1"
    private static let limit = 8

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    @discardableResult
    static func remember(_ term: String) -> [String] {
        let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return load() }
        var values = load().filter { $0.caseInsensitiveCompare(clean) != .orderedSame }
        values.insert(clean, at: 0)
        values = Array(values.prefix(limit))
        UserDefaults.standard.set(values, forKey: key)
        return values
    }

    @discardableResult
    static func clear() -> [String] {
        UserDefaults.standard.removeObject(forKey: key)
        return []
    }
}
