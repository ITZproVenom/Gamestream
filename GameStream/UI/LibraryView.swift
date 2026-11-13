import SwiftUI

struct LibraryView: View {
    enum Shelf: String, CaseIterable, Identifiable {
        case allGames, favorites, recents, queue, lists

        var id: String { rawValue }

        var title: String {
            switch self {
            case .favorites: return "Favorites"
            case .recents: return "Recent"
            case .queue: return "Up next"
            case .lists: return "Lists"
            case .allGames: return "All games"
            }
        }

        var icon: String {
            switch self {
            case .favorites: return "heart.fill"
            case .recents: return "clock.fill"
            case .queue: return "text.line.first.and.arrowtriangle.forward"
            case .lists: return "folder.fill"
            case .allGames: return "square.grid.2x2.fill"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case custom, title, playtime

        var id: String { rawValue }

        var title: String {
            switch self {
            case .custom: return "Default order"
            case .title: return "Title"
            case .playtime: return "Most played"
            }
        }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var stream: StreamCoordinator

    @State private var shelf: Shelf = .favorites
    @State private var sort: Sort = .custom
    @State private var genre: String?
    @State private var newListName = ""
    @State private var showingNewList = false
    /// The filtered and sorted games, worked out when something changes
    /// rather than on every redraw.
    @State private var visibleGames: [Game] = []
    @State private var genres: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 190), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dashboard

                    shelfPicker

                    if shelf == .lists {
                        ListsSection(showingNewList: $showingNewList)
                    } else {
                        if !genres.isEmpty {
                            genreFilter
                        }
                        gamesGrid
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 36)
                // The page is exactly as wide as the screen, whatever a
                // child would prefer. Without this one greedy row drags
                // every other row off the right edge with it.
                .containerRelativeFrame(.horizontal)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AuroraBackground() }
            // Unfavouriting the last racing game used to leave "Racing"
            // selected and invisible, so the shelf looked empty and said
            // there were no favourites at all.
            .onChange(of: genres) { _, names in
                if let genre, !names.contains(genre) { self.genre = nil }
            }
            // The library opened on Favourites, which is empty for almost
            // everyone: the first thing on the screen was an empty state
            // with nothing else on it. It now opens on the first shelf that
            // has something in it.
            .task {
                if library.favorites.isEmpty {
                    shelf = library.recents.isEmpty ? .allGames : .recents
                }
                await refresh()
            }
            .task(id: refreshKey) { await refresh() }
            .navigationTitle("Library")
            .toolbar {
                if shelf == .lists {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNewList = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("New list")
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(Sort.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Sort")
                    }
                }
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameList.self) { ListDetailView(list: $0) }
            .alert("New list", isPresented: $showingNewList) {
                TextField("Name", text: $newListName)
                Button("Create") {
                    library.createList(named: newListName)
                    newListName = ""
                }
                Button("Cancel", role: .cancel) { newListName = "" }
            } message: {
                Text("Group games however you like — a backlog, co-op night, anything.")
            }
        }
    }

    // MARK: - Pieces

    private var shelfPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(Shelf.allCases) { option in
                    FilterChip(title: option.title, isSelected: shelf == option) {
                        withAnimation(.smooth) {
                            shelf = option
                            genre = nil
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pageInset)
        }
        .scrollIndicators(.hidden)
    }

    private var genreFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                FilterChip(title: "All genres", isSelected: genre == nil) {
                    withAnimation(.smooth) { genre = nil }
                }
                ForEach(availableGenres, id: \.self) { name in
                    FilterChip(title: name, isSelected: genre == name) {
                        withAnimation(.smooth) { genre = (genre == name) ? nil : name }
                    }
                }
            }
            .padding(.horizontal, Theme.pageInset)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var gamesGrid: some View {
        if games.isEmpty {
            if shelf == .allGames, catalog.isLoading {
                LoadingNotice()
            } else if shelf == .allGames, let error = catalog.errorMessage {
                ErrorNotice(title: "Catalog unavailable", message: error) {
                    Task { await catalog.refresh() }
                }
                .padding(.horizontal, Theme.pageInset)
            } else {
                emptyState
            }
        } else {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(games) { game in
                    GameTile(game: game) { stream.play(game) }
                        .contextMenu { menu(for: game) }
                }
            }
            .padding(.horizontal, Theme.pageInset)
        }
    }

    @ViewBuilder
    private func menu(for game: Game) -> some View {
        Button {
            stream.play(game)
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        Button {
            library.toggleFavorite(game)
        } label: {
            Label(library.isFavorite(game) ? "Remove favorite" : "Add favorite",
                  systemImage: library.isFavorite(game) ? "heart.slash" : "heart")
        }
        Button {
            library.toggleQueue(game)
        } label: {
            Label(library.isQueued(game) ? "Remove from Up next" : "Add to Up next",
                  systemImage: library.isQueued(game) ? "minus.circle" : "text.badge.plus")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch shelf {
        case .favorites:
            EmptyNotice(systemImage: "heart",
                        title: "No favorites yet",
                        message: "Tap the heart on any game and it will wait for you here.")
        case .recents:
            EmptyNotice(systemImage: "clock",
                        title: "Nothing played yet",
                        message: "Games you stream show up here so you can pick them back up.")
        case .queue:
            EmptyNotice(systemImage: "text.badge.plus",
                        title: "Up next is empty",
                        message: "Queue a few games and the player can roll straight into the next one.")
        case .lists:
            EmptyView()
        case .allGames:
            EmptyNotice(systemImage: "square.grid.2x2",
                        title: "Catalog is loading",
                        message: "Cloud games will appear here when the catalog is ready.")
        }
    }

    // MARK: - Dashboard

    /// The Library opened on an empty shelf, which is why it looked empty:
    /// Favourites is empty for almost everyone, so the first thing on the
    /// screen was a notice saying there was nothing in it. The things the
    /// player actually has - what they were playing, what is queued, what
    /// they marked - are now on the screen before the shelves.
    @ViewBuilder
    private var dashboard: some View {
        if !library.recents.isEmpty, shelf != .recents {
            VStack(alignment: .leading, spacing: 10) {
                header("Jump back in", detail: "Where you left off")
                GameShelf(games: Array(library.recents.prefix(12))) { game in
                    let played = library.playtime(forGameID: game.id)
                    return played > 0 ? Format.duration(played) : nil
                }
            }
        }

        if !library.queue.isEmpty, shelf != .queue {
            VStack(alignment: .leading, spacing: 10) {
                header("Up next", detail: queueDetail)
                GameShelf(games: library.queue)
            }
        }

        if !library.favorites.isEmpty, shelf != .favorites {
            VStack(alignment: .leading, spacing: 10) {
                header("Favorites", detail: "\(library.favorites.count) saved")
                GameShelf(games: Array(library.favorites.prefix(12)))
            }
        }
    }

    private func header(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.pageInset)
    }

    /// How long the queue is likely to take, from how long this player
    /// usually plays.
    private var queueDetail: String {
        guard !library.queue.isEmpty else { return "" }
        let count = library.queue.count
        let estimate = library.queueEstimatedLength
        let noun = count == 1 ? "game" : "games"
        guard estimate > 0 else { return "\(count) \(noun)" }
        return "\(count) \(noun) · about \(Format.duration(estimate)) left"
    }

    // MARK: - Data

    private var source: [Game] {
        switch shelf {
        case .favorites: return library.favorites
        case .recents: return library.recents
        case .queue: return library.queue
        case .lists: return []
        case .allGames: return catalog.games
        }
    }

    /// Everything the filtered list depends on, as one value.
    ///
    /// The grid used to filter and sort the whole catalogue on every
    /// redraw - and the sort asked the library for the playtime of two
    /// games at a time, which walked the entire activity log. On a
    /// catalogue of five hundred games that was thousands of string
    /// comparisons a frame, and the grid stuttered under the thumb.
    private var refreshKey: String {
        "\(shelf.rawValue)|\(sort.rawValue)|\(genre ?? "")|"
            + "\(library.favorites.count)|\(library.recents.count)|\(library.queue.count)|"
            + "\(catalog.games.count)|\(library.activity.count)"
    }

    private func refresh() async {
        let all = source
        let names = Array(Set(all.map(\.genre))).sorted()
        var result = all
        if let genre {
            result = result.filter { $0.genre == genre }
        }
        switch sort {
        case .custom:
            break
        case .title:
            result = result.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .playtime:
            // One lookup per game, rather than one per comparison.
            var played: [String: TimeInterval] = [:]
            for game in result {
                played[game.id.lowercased()] = library.playtime(forGameID: game.id)
            }
            result = result.sorted {
                (played[$0.id.lowercased()] ?? 0) > (played[$1.id.lowercased()] ?? 0)
            }
        }
        genres = names
        visibleGames = result
    }

    private var games: [Game] { visibleGames }
    private var availableGenres: [String] { genres }
}

/// The Lists shelf: user-made collections.
struct ListsSection: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog

    @Binding var showingNewList: Bool

    var body: some View {
        VStack(spacing: 14) {
            if library.lists.isEmpty {
                EmptyNotice(systemImage: "folder.badge.plus",
                            title: "No lists yet",
                            message: "Lists are yours to shape: a backlog, a co-op night, "
                                + "a shortlist of things to try.",
                            actionTitle: "Create a list") { showingNewList = true }
            } else {
                ForEach(library.lists) { list in
                    NavigationLink(value: list) {
                        GlassCard {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(.tint.opacity(0.18)).frame(width: 44, height: 44)
                                    Image(systemName: "folder.fill").foregroundStyle(.tint)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(list.name)
                                        .font(.headline)
                                    Text("\(list.gameIDs.count) game\(list.gameIDs.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            library.deleteList(list)
                        } label: {
                            Label("Delete list", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pageInset)
    }
}

struct ListDetailView: View {
    let list: GameList

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var stream: StreamCoordinator

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 190), spacing: 16)]

    var body: some View {
        ScrollView {
            let games = library.games(in: current, catalog: catalog)
            if games.isEmpty {
                EmptyNotice(systemImage: "square.stack.3d.up.slash",
                            title: "This list is empty",
                            message: "Open any game and use “Add to list” to put it here.")
            } else {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(games) { game in
                        GameTile(game: game) { stream.play(game) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    library.toggle(game: game, inListWithID: current.id)
                                } label: {
                                    Label("Remove from list", systemImage: "minus.circle")
                                }
                            }
                    }
                }
                .padding(Theme.pageInset)
                .containerRelativeFrame(.horizontal)
            }
        }
        .background { AuroraBackground() }
        .navigationTitle(current.name)
        .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
    }

    /// Always read the live copy, so renames and removals are reflected.
    private var current: GameList {
        library.list(withID: list.id) ?? list
    }
}
