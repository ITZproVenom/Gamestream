import SwiftUI

/// New game detail surface. Play / Open Cloud go through existing SessionStore → StreamPlayerView.
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

    private var related: [CatalogGame] { GameCatalog.related(to: game) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    actions
                    aboutCard
                    if !related.isEmpty { relatedShelf }
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .background(Color.black.opacity(0.94).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    Text(game.title)
                        .font(.headline)
                        .lineLimit(1)
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
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(game.provider)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: Capsule())
                Text(game.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(game.tagline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                // LOCKED PATH: SessionStore.playCatalogGame → existing StreamPlayerView
                session.playCatalogGame(game)
                onClose()
            } label: {
                Label("Play now", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)

            HStack(spacing: 10) {
                Button { session.toggleFavorite(game.tracked) } label: {
                    Label(
                        session.isFavorite(game.id) ? "Favorited" : "Favorite",
                        systemImage: session.isFavorite(game.id) ? "star.fill" : "star"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glass)

                Button { session.toggleQueue(game.tracked) } label: {
                    Text(session.isQueued(game.id) ? "Queued" : "Up Next")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
            }

            HStack(spacing: 10) {
                Button {
                    if lists.collections.isEmpty { showingNewList = true }
                    else { showingLists = true }
                } label: {
                    Text(lists.collections.isEmpty ? "New list" : "Lists")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)

                Button {
                    session.openCatalogGame(game)
                    onClose()
                } label: {
                    Text("Xbox page")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About").font(.title3.weight(.bold))
            Text(game.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let stat = activity.stat(for: game.id) {
                Text("\(PlayActivityStore.format(stat.totalSeconds)) played · \(stat.sessionCount) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                glassPill(game.genre)
                glassPill(game.provider)
                if session.isFavorite(game.id) { glassPill("Favorite") }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More like this").font(.title3.weight(.bold))
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

    private func glassPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
    }
}
