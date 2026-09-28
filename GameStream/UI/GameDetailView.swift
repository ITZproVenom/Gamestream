import SwiftUI

struct GameDetailView: View {
    let game: Game

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var stream: StreamCoordinator

    @State private var showingLists = false
    @State private var playingNatively = false
    @Namespace private var glass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                actions
                facts

                if !game.tagline.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About").font(.headline)
                        Text(game.tagline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.pageInset)
                }

                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionHeader(title: "More \(game.genre)")
                            .padding(.horizontal, Theme.pageInset)
                        GameShelf(games: related)
                    }
                }
            }
            .padding(.bottom, 40)
            // The page is exactly as wide as the screen, whatever a child
            // would prefer.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background { AuroraBackground() }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingLists = true
                    } label: {
                        Label("Add to list", systemImage: "folder.badge.plus")
                    }
                    if let url = game.storeURL {
                        Link(destination: url) {
                            Label("Open on xbox.com", systemImage: "safari")
                        }
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More actions")
            }
        }
        #if canImport(WebRTC)
        .fullScreenCover(isPresented: $playingNatively) {
            NativeStreamView(game: game)
        }
        #endif
        .sheet(isPresented: $showingLists) {
            ListPickerView(game: game)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // No background extension effect here. It widens the view beyond
            // the screen, and because everything below shares the scroll
            // view's content width, the whole page ended up shifted off the
            // left edge with the poster and stat cards cut in half.
            GameArtwork(url: game.heroURL ?? game.posterURL, cornerRadius: 0)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [.init(color: .black.opacity(0), location: 0.35),
                                .init(color: .black.opacity(0.85), location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }

            HStack(alignment: .bottom, spacing: 14) {
                GameArtwork(url: game.posterURL, cornerRadius: 14)
                    .frame(width: 86, height: 115)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(game.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    Text(game.genre)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(Theme.pageInset)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        // A plain stack. GlassEffectContainer has no intrinsic width here and
        // stretched the scroll view's content past the screen, which is what
        // pushed this page off its left edge.
        Group {
            HStack(spacing: 13) {
                Button {
                    stream.play(game)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .glassEffectID("play", in: glass)

                #if canImport(WebRTC)
                // The native player, while it is still proving itself. It
                // shares nothing with the webview path, so a failure here
                // cannot take the working one down with it.
                GlassIconButton(systemImage: "bolt.fill", label: "Play natively") {
                    playingNatively = true
                }
                .glassEffectID("native", in: glass)
                #endif

                GlassIconButton(systemImage: library.isFavorite(game) ? "heart.fill" : "heart",
                                label: library.isFavorite(game) ? "Remove favorite" : "Add favorite") {
                    withAnimation(.smooth) { library.toggleFavorite(game) }
                }
                .glassEffectID("favorite", in: glass)

                GlassIconButton(systemImage: library.isQueued(game)
                                ? "text.badge.minus" : "text.badge.plus",
                                label: library.isQueued(game) ? "Remove from Up next" : "Add to Up next") {
                    withAnimation(.smooth) { library.toggleQueue(game) }
                }
                .glassEffectID("queue", in: glass)
            }
        }
        .padding(.horizontal, Theme.pageInset)
    }

    // MARK: - Facts

    private var facts: some View {
        HStack(spacing: 12) {
            StatChip(value: playtime > 0 ? Format.duration(playtime) : "—",
                     caption: "Your playtime",
                     systemImage: "clock.fill")
            StatChip(value: "\(sessions)",
                     caption: sessions == 1 ? "Session" : "Sessions",
                     systemImage: "play.rectangle.fill")
            StatChip(value: library.isQueued(game) ? "Queued" : "Ready",
                     caption: "Status",
                     systemImage: "cloud.fill")
        }
        .padding(.horizontal, Theme.pageInset)
    }

    private var playtime: TimeInterval { library.playtime(forGameID: game.id) }
    private var sessions: Int { library.sessions(forGameID: game.id) }

    private var related: [Game] {
        catalog.games(inGenre: game.genre)
            .filter { !$0.matches(id: game.id) }
            .prefix(12)
            .map { $0 }
    }
}

/// Choose which lists a game belongs to.
struct ListPickerView: View {
    let game: Game

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var newListName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(library.lists) { list in
                        Button {
                            library.toggle(game: game, inListWithID: list.id)
                        } label: {
                            HStack {
                                Text(list.name)
                                Spacer()
                                if library.contains(game: game, inListWithID: list.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(library.lists.isEmpty ? "" : "Your lists")
                }

                Section("New list") {
                    HStack {
                        TextField("Name", text: $newListName)
                        Button("Add") {
                            library.createList(named: newListName)
                            newListName = ""
                        }
                        .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Every logged session, newest first.
struct ActivityView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if library.activity.isEmpty {
                    EmptyNotice(systemImage: "list.bullet.rectangle",
                                title: "No sessions yet",
                                message: "Sessions longer than fifteen seconds are recorded here.")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(library.activity) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(Format.duration(record.seconds))
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !library.activity.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) { library.clearActivity() }
                    }
                }
            }
        }
    }
}
