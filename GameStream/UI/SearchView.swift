import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var stream: StreamCoordinator
    @StateObject private var history = SearchHistory.shared

    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 190), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if query.isEmpty {
                        idleContent
                    } else if results.isEmpty {
                        EmptyNotice(systemImage: "magnifyingglass",
                                    title: "No matches",
                                    message: "Nothing in the cloud catalog matches “\(query)”. "
                                        + "Titles come and go from Game Pass, so it may have left.")
                    } else {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.pageInset)

                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(results) { game in
                                GameTile(game: game) { stream.play(game) }
                            }
                        }
                        .padding(.horizontal, Theme.pageInset)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AuroraBackground() }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Games, genres, anything")
            .searchToolbarBehavior(.minimize)
            .onSubmit(of: .search) { history.record(query) }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
        }
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

    private var results: [Game] {
        catalog.search(query)
    }
}
