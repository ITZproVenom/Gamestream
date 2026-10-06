import SwiftUI

struct LibraryView: View {
    enum Shelf: String, CaseIterable, Identifiable {
        case favorites, recents, queue, lists

        var id: String { rawValue }

        var title: String {
            switch self {
            case .favorites: return "Favorites"
            case .recents: return "Recent"
            case .queue: return "Up next"
            case .lists: return "Lists"
            }
        }

        var icon: String {
            switch self {
            case .favorites: return "heart.fill"
            case .recents: return "clock.fill"
            case .queue: return "text.line.first.and.arrowtriangle.forward"
            case .lists: return "folder.fill"
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

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 190), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    shelfPicker

                    if shelf == .lists {
                        ListsSection(showingNewList: $showingNewList)
                    } else {
                        if !availableGenres.isEmpty {
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
            .onChange(of: availableGenres) { _, names in
                if let genre, !names.contains(genre) { self.genre = nil }
            }
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
            emptyState
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
        }
    }

    // MARK: - Data

    private var source: [Game] {
        switch shelf {
        case .favorites: return library.favorites
        case .recents: return library.recents
        case .queue: return library.queue
        case .lists: return []
        }
    }

    private var availableGenres: [String] {
        Array(Set(source.map(\.genre))).sorted()
    }

    private var games: [Game] {
        var result = source
        if let genre {
            result = result.filter { $0.genre == genre }
        }
        switch sort {
        case .custom:
            return result
        case .title:
            return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .playtime:
            return result.sorted { library.playtime(forGameID: $0.id) > library.playtime(forGameID: $1.id) }
        }
    }
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
