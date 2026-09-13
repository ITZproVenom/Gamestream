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

// MARK: - Settings (actually useful)

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore

    @State private var streamResolution = SessionStore.storedResolution
    @State private var serverRegion = SessionStore.storedRegion
    @State private var showClearConfirm = false
    @State private var statusMessage: String?

    private let resolutionOptions = ["Auto", "720p", "1080p", "1080p HQ"]
    private let regionOptions = ["Auto", "North America", "Europe", "Asia", "Australia"]

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.3"
        let build = info?["CFBundleVersion"] as? String ?? "4"
        return "\(short) (\(build))"
    }

    var body: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 8)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                    sectionHeader("Account")
                    GlassRow(title: "Signed in as", value: session.accountLabel ?? "Not signed in")

                    sectionHeader("Device")
                    keepAwakeRow

                    sectionHeader("Library")
                    Text("Favorites and recently played stay on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                    GlassRow(title: "Favorites", value: "\(session.favorites.count)")
                    GlassRow(title: "Recently played", value: "\(session.recents.count)")

                    actionButton(icon: "clock.arrow.circlepath", title: "Clear recently played", tint: .primary) {
                        session.clearRecents()
                        flash("Recently played cleared.")
                    }
                    actionButton(icon: "star.slash", title: "Clear favorites", tint: .orange) {
                        session.clearFavorites()
                        flash("Favorites cleared.")
                    }

                    sectionHeader("Stream")
                    Text("These apply to Better xCloud and take effect after the page reloads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)

                    chipSection(
                        title: "Target resolution",
                        options: resolutionOptions,
                        selection: $streamResolution
                    ) { option in
                        session.applyStreamResolution(option)
                        flash("Resolution set to \(option). Reloading…")
                    }

                    chipSection(
                        title: "Server region",
                        options: regionOptions,
                        selection: $serverRegion
                    ) { option in
                        session.applyServerRegion(option)
                        flash("Region set to \(option). Reloading…")
                    }

                    sectionHeader("Actions")

                    actionButton(icon: "house.fill", title: "Open Library", tint: .primary) {
                        session.openHome()
                    }

                    actionButton(icon: "arrow.triangle.2.circlepath", title: "Refresh Better xCloud script", tint: .primary) {
                        session.refreshBetterXCloudScript()
                        flash("Script cache cleared. Reloading…")
                    }

                    actionButton(icon: "trash", title: "Clear web data", tint: .orange) {
                        showClearConfirm = true
                    }

                    if session.isSignedIn {
                        actionButton(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", tint: .red) {
                            session.signOut()
                            flash("Signed out.")
                        }
                    }

                    sectionHeader("About")
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("GameStream")
                                .font(.headline)
                                .lineLimit(1)
                                .layoutPriority(1)
                            Spacer(minLength: 8)
                            Text(appVersionLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .multilineTextAlignment(.trailing)
                        }
                        Text("Native iOS 26 client for Xbox Cloud Gaming with Better xCloud built in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Full stream options (stats, touch controls, clarity, Remote Play) live in the Better xCloud menu on the Xbox page — look near your profile for the server button.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .confirmationDialog(
            "Clear all Xbox website data and cookies? You will need to sign in again.",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear web data", role: .destructive) {
                session.clearWebData()
                flash("Web data cleared.")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var keepAwakeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep screen awake")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Prevents sleep while GameStream is open, not only during a stream.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("Keep screen awake", isOn: $session.keepScreenAwake)
                .labelsHidden()
                .tint(.green)
                .accessibilityLabel("Keep screen awake")
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .padding(.top, 4)
    }

    private func chipSection(
        title: String,
        options: [String],
        selection: Binding<String>,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            selection.wrappedValue = option
                            onSelect(option)
                        } label: {
                            Text(option)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        .opacity(selection.wrappedValue == option ? 1.0 : 0.5)
                    }
                }
            }
        }
    }

    private func actionButton(icon: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(tint)
            .padding(16)
        }
        .buttonStyle(.glass)
    }

    private func flash(_ message: String) {
        withAnimation { statusMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { statusMessage = nil }
        }
    }
}

struct GlassRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
