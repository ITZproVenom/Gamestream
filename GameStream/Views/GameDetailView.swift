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
            // Static fill — a second aurora Timeline under the sheet doubles main-thread
            // compositing and is a common source of hub lag while the sheet is open.
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
                            .background(.ultraThinMaterial, in: Circle())
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
                    .background(.ultraThinMaterial, in: Capsule())
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
                session.toggleQueued(game.tracked)
            } label: {
                Text(session.isQueued(game.id) ? "Remove from Up Next" : "Add to Up Next")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.glass)

            Button {
                showingLists = true
            } label: {
                Text("Add to list")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.glass)

            Button {
                showingNewList = true
            } label: {
                Text("New list with this game")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.glass)
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !game.genres.isEmpty {
                Text(game.genres.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let minutes = activity.minutes(for: game.id), minutes > 0 {
                Text("Played about \(minutes) min on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More like this")
                .font(.headline)
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
}
