import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var stream: StreamCoordinator

    let game: Game

    @State private var showingLists = false

    private var playtime: TimeInterval { library.playtime(forGameID: game.id) }
    private var related: [Game] {
        catalog.games(inGenre: game.genre).filter { !$0.matches(id: game.id) }.prefix(10).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GameArtwork(url: game.heroURL ?? game.posterURL, cornerRadius: 20)
                    .aspectRatio(16 / 9, contentMode: .fit)

                VStack(alignment: .leading, spacing: 9) {
                    Text(game.title)
                        .font(.title.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Pill(text: game.genre)
                        Pill(text: "Cloud")
                        if playtime > 0 {
                            Pill(text: Format.duration(playtime) + " played")
                        }
                    }

                    if !game.tagline.isEmpty {
                        Text(game.tagline)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                actions

                if !related.isEmpty {
                    // Safe to push another detail screen: the destination for
                    // Game is declared once, at the root of the stack.
                    SectionHeader(title: "More \(game.genre)")
                    HorizontalGameRow(games: related)
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLists) {
            ListPickerView(game: game)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    stream.play(game)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    library.toggleFavorite(game)
                } label: {
                    Image(systemName: library.isFavorite(game) ? "star.fill" : "star")
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel(library.isFavorite(game) ? "Remove from favorites" : "Add to favorites")
            }

            HStack(spacing: 12) {
                Button {
                    library.toggleQueue(game)
                } label: {
                    Label(library.isQueued(game) ? "In Up Next" : "Add to Up Next",
                          systemImage: library.isQueued(game) ? "checkmark" : "text.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingLists = true
                } label: {
                    Label("Lists", systemImage: "square.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct ListPickerView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var newName = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if library.lists.isEmpty {
                    ContentUnavailableView(
                        "No lists yet",
                        systemImage: "square.stack",
                        description: Text("Create one to group games however you like.")
                    )
                } else {
                    ForEach(library.lists) { list in
                        Button {
                            library.toggle(game: game, inListWithID: list.id)
                        } label: {
                            HStack {
                                Text(list.name).foregroundStyle(.primary)
                                Spacer()
                                if library.contains(game: game, inListWithID: list.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New") { newName = ""; creating = true }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New list", isPresented: $creating) {
                TextField("List name", text: $newName)
                Button("Create") { library.createList(named: newName) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct ListsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if library.lists.isEmpty {
                    ContentUnavailableView(
                        "No lists yet",
                        systemImage: "square.stack",
                        description: Text("Lists are a way to group games for later.")
                    )
                } else {
                    ForEach(library.lists) { list in
                        NavigationLink {
                            ListDetailView(listID: list.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(list.name).font(.headline)
                                Text("\(list.gameIDs.count) game\(list.gameIDs.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { library.deleteList(library.lists[index]) }
                    }
                }
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { newName = ""; creating = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New list", isPresented: $creating) {
                TextField("List name", text: $newName)
                Button("Create") { library.createList(named: newName) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct ListDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var stream: StreamCoordinator
    let listID: UUID

    private var list: GameList? { library.list(withID: listID) }

    var body: some View {
        List {
            if let list {
                let games = library.games(in: list, catalog: catalog)
                if games.isEmpty {
                    ContentUnavailableView(
                        "This list is empty",
                        systemImage: "square.stack",
                        description: Text("Add games from any game's page.")
                    )
                } else {
                    ForEach(games) { game in
                        HStack {
                            GameRow(game: game)
                            Button {
                                stream.play(game)
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Play \(game.title)")
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                library.toggle(game: game, inListWithID: listID)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(list?.name ?? "List")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ActivityView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if library.activity.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "clock",
                        description: Text("Play a game and your sessions appear here.")
                    )
                } else {
                    Section {
                        LabeledContent("Total", value: Format.duration(library.totalPlaytime))
                        LabeledContent("Sessions", value: "\(library.activity.count)")
                    }
                    Section("Sessions") {
                        ForEach(library.activity) { record in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title).font(.subheadline.weight(.semibold))
                                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(Format.duration(record.seconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !library.activity.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) { library.clearActivity() }
                    }
                }
            }
        }
    }
}
