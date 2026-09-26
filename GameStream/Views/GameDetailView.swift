import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var artwork = ArtworkStore.shared
    @ObservedObject private var lists = CollectionStore.shared
    @ObservedObject private var activity = PlayActivityStore.shared
    @State private var showingLists = false
    @State private var newListName = ""
    @State private var showingNewList = false
    let game: CatalogGame
    var onClose: () -> Void

    private var related: [CatalogGame] {
        GameCatalog.related(to: game)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    actions
                    meta
                    if !related.isEmpty {
                        relatedShelf
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            // Static fill — a second aurora under the sheet doubles compositing cost.
            .background {
                Color.black.opacity(0.92).ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    Text(game.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .onAppear { artwork.load(game.id) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingLists) {
            ListsBrowserView { item in
                session.playCatalogGame(item)
                showingLists = false
                onClose()
            }
            .environmentObject(session)
        }
        .alert("New list", isPresented: $showingNewList) {
            TextField("Weekend co-op", text: $newListName)
            Button("Create") {
                if let created = lists.create(named: newListName) {
                    lists.toggle(game: game.tracked, inCollection: created.id)
                }
                newListName = ""
            }
            Button("Cancel", role: .cancel) { newListName = "" }
        } message: {
            Text("Save \(game.title) into a named list.")
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GameArtView(url: artwork.url(for: game.id), accent: game.accent, title: game.title)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(game.provider)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: Capsule())
                    .lineLimit(1)
                Text(game.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(game.tagline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    session.playCatalogGame(game)
                    onClose()
                } label: {
                    Text("Play now")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("Play \(game.title)")

                Button {
                    session.toggleFavorite(game.tracked)
                } label: {
                    Image(systemName: session.isFavorite(game.id) ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 48, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(session.isFavorite(game.id) ? "Remove favorite" : "Add favorite")
            }

            Button {
                session.toggleQueue(game.tracked)
            } label: {
                Text(session.isQueued(game.id) ? "Remove from Up Next" : "Add to Up Next")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(session.isQueued(game.id) ? "Remove \(game.title) from Up Next" : "Add \(game.title) to Up Next")

            HStack(spacing: 8) {
                Button {
                    if lists.collections.isEmpty {
                        showingNewList = true
                    } else {
                        showingLists = true
                    }
                } label: {
                    Text(lists.collections.isEmpty ? "New list" : "Lists")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Open lists")

                if !lists.collections.isEmpty {
                    Menu {
                        ForEach(lists.collections) { list in
                            Button {
                                lists.toggle(game: game.tracked, inCollection: list.id)
                            } label: {
                                Label(
                                    lists.contains(game.id, inCollection: list.id) ? "Remove from \(list.name)" : "Add to \(list.name)",
                                    systemImage: lists.contains(game.id, inCollection: list.id) ? "checkmark" : "plus"
                                )
                            }
                        }
                        Button {
                            showingNewList = true
                        } label: {
                            Label("New list", systemImage: "plus")
                        }
                    } label: {
                        Text("Add to list")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Add \(game.title) to a list")
                }
            }

            Button {
                session.openCatalogGame(game)
                onClose()
            } label: {
                Text("Open on Xbox Cloud")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open \(game.title) on Xbox Cloud")
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(game.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let stat = activity.stat(for: game.id) {
                Text("\(PlayActivityStore.format(stat.totalSeconds)) played · \(stat.sessionCount) sessions · \(PlayActivityStore.format(stat.weekSeconds)) this week")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                pill(game.genre)
                pill(game.provider)
                if session.isFavorite(game.id) { pill("Favorite") }
                if session.recents.contains(where: { $0.id == game.id }) { pill("Played") }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More like this")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(related) { item in
                        Button {
                            session.playCatalogGame(item)
                            onClose()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                GameArtView(url: artwork.url(for: item.id), accent: item.accent, title: item.title)
                                    .frame(width: 110, height: 148)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Text(item.title)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(2)
                                    .frame(width: 110, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .onAppear { artwork.load(item.id) }
                    }
                }
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
    }
}
