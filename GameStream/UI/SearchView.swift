import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var history = SearchHistory.shared

    @State private var query = ""
    @State private var showingXboxResults = false
    @State private var searchReloadToken = 0
    @State private var submittedSearchURL: URL?
    @StateObject private var navigator = RootView.Navigator.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if query.isEmpty {
                        idleContent
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Search Xbox Cloud Gaming",
                                          subtitle: "Live results from Xbox.com")
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Search Xbox's current cloud catalog for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button(action: openXboxResults) {
                                        Label("View live Xbox results", systemImage: "magnifyingglass")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.glassProminent)
                                    .buttonBorderShape(.capsule)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.pageInset)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 36)
                // The page is exactly as wide as the screen, whatever a
                // child would prefer. Without this one greedy row drags
                // every other row off the right edge with it.
                .containerRelativeFrame(.horizontal)
            }
            .refreshable { await catalog.refresh() }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AuroraBackground() }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Games, genres, anything")
            .searchToolbarBehavior(.minimize)
            .onSubmit(of: .search) { openXboxResults() }
            // A search handed in from a Shortcut or a link arrives here.
            .onChange(of: navigator.searchSeed) { _, seed in
                guard let seed, !seed.isEmpty else { return }
                query = seed
                navigator.searchSeed = nil
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .sheet(isPresented: $showingXboxResults) {
                NavigationStack {
                    XboxWebView(role: .browse,
                                url: submittedSearchURL ?? XboxAuth.playURL,
                                reloadToken: searchReloadToken)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Xbox Cloud Search")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingXboxResults = false }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    searchReloadToken &+= 1
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .accessibilityLabel("Reload Xbox search")
                            }
                        }
                }
            }
        }
    }

    private func openXboxResults() {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        history.record(clean)
        var components = URLComponents(string: "https://www.xbox.com/play/search")
        components?.queryItems = [URLQueryItem(name: "q", value: clean)]
        guard let url = components?.url else { return }
        submittedSearchURL = url
        showingXboxResults = true
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
