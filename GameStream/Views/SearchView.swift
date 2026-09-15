import SwiftUI

struct SearchView: View {
    @EnvironmentObject var session: SessionStore
    @FocusState private var searchFocused: Bool
    @State private var recent: [String] = SessionStore.recentSearches

    private let popularTitles = [
        "Fortnite",
        "Minecraft",
        "Call of Duty",
        "Forza Horizon",
        "Roblox",
        "Sea of Thieves"
    ]

    var body: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Search")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text("Find your next game")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField("Search games", text: Binding(
                            get: { session.searchDraft },
                            set: { session.updateSearchDraft($0) }
                        ))
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 17, weight: .medium))
                            .submitLabel(.search)
                            .onSubmit { performSearch() }

                        if !session.searchDraft.isEmpty {
                            Button { session.updateSearchDraft("") } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .glassEffect(
                        searchFocused ? .regular.interactive() : .regular,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                    if session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !session.favorites.isEmpty {
                            gameShelf(title: "Favorites", games: session.favorites, empty: nil)
                        }
                        if !session.recents.isEmpty {
                            gameShelf(title: "Recently played", games: session.recents, empty: nil)
                        }
                        popularSection
                        if recent.isEmpty && session.favorites.isEmpty && session.recents.isEmpty {
                            emptyState
                        } else if !recent.isEmpty {
                            recentSection
                        }
                    } else {
                        resultsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { recent = SessionStore.recentSearches }
    }

    private func gameShelf(title: String, games: [TrackedGame], empty: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            ForEach(games) { game in
                HStack(spacing: 10) {
                    Button {
                        session.openGame(game)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: title == "Favorites" ? "star.fill" : "clock.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text("Open in Library")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.glass)

                    Button {
                        session.toggleFavorite(game)
                    } label: {
                        Image(systemName: session.isFavorite(game.id) ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 42, height: 52)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(session.isFavorite(game.id) ? "Remove favorite" : "Add favorite")
                }
            }

            if let empty, games.isEmpty {
                Text(empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular on Cloud")
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popularTitles, id: \.self) { title in
                        Button {
                            session.updateSearchDraft(title)
                            performSearch()
                        } label: {
                            Text(title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("What are you playing?")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("Search for any game available on Xbox Cloud Gaming. Pin titles from Library to keep them here.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent searches")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Button("Clear") {
                    SessionStore.clearRecentSearches()
                    recent = []
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }

            ForEach(recent, id: \.self) { item in
                Button {
                    session.updateSearchDraft(item)
                    performSearch()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { performSearch() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                    Text("Search Xbox Cloud Gaming")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
            }
            .buttonStyle(.glassProminent)

            let matches = (session.favorites + session.recents)
                .reduce(into: [TrackedGame]()) { acc, game in
                    if !acc.contains(where: { $0.id == game.id }),
                       game.title.localizedCaseInsensitiveContains(session.searchDraft) {
                        acc.append(game)
                    }
                }

            if !matches.isEmpty {
                Text("From your library")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 6)
                gameShelf(title: "Matches", games: matches, empty: nil)
            }

            Text("Results")
                .font(.title3.weight(.semibold))
                .padding(.top, 6)

            Text("Tap above to search Xbox Cloud Gaming for \"\(session.searchDraft)\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func performSearch() {
        let query = session.searchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchFocused = false
        SessionStore.rememberSearch(query)
        recent = SessionStore.recentSearches
        session.openSearch(query: query)
    }
}
