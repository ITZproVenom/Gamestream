import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var auth: XboxAuth

    @Binding var showingBrowser: Bool
    @State private var showingActivity = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    header

                    if let error = catalog.errorMessage, catalog.games.isEmpty {
                        ErrorNotice(title: "Catalog unavailable", message: error) {
                            Task { await catalog.refresh() }
                        }
                    } else if catalog.games.isEmpty && catalog.isLoading {
                        LoadingNotice()
                    }

                    if let featured = catalog.games.first {
                        FeaturedCard(game: featured) { stream.play(featured) }
                    }

                    // Recents and favourites come from the library itself, so
                    // they are present even when the catalog request fails.
                    if !library.recents.isEmpty {
                        SectionHeader(title: "Continue playing",
                                      actionTitle: "Activity") { showingActivity = true }
                        HorizontalGameRow(games: Array(library.recents.prefix(12)))
                    }

                    if !library.favorites.isEmpty {
                        SectionHeader(title: "Favorites")
                        HorizontalGameRow(games: Array(library.favorites.prefix(12)))
                    }

                    if !library.queue.isEmpty {
                        SectionHeader(title: "Up next")
                        HorizontalGameRow(games: library.queue)
                    }

                    if settings.showActivity && !library.activity.isEmpty {
                        activitySummary
                    }

                    if !catalog.games.isEmpty {
                        SectionHeader(title: "Popular now")
                        HorizontalGameRow(games: Array(catalog.games.prefix(20)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await catalog.refresh() }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .sheet(isPresented: $showingActivity) { ActivityView() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting).font(.largeTitle.weight(.bold))
                Text(auth.state.gamertag ?? "Xbox Cloud Gaming")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingBrowser = true
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Open xbox.com")
        }
        .padding(.top, 8)
    }

    private var activitySummary: some View {
        Button {
            showingActivity = true
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Your activity").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                Text("\(Format.duration(library.totalPlaytime)) played across "
                     + "\(library.activity.count) session\(library.activity.count == 1 ? "" : "s").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(17)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<12: return "Good morning"
        case ..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

struct FeaturedCard: View {
    let game: Game
    let play: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GameArtwork(url: game.heroURL ?? game.posterURL, cornerRadius: 22)
                .frame(height: 220)
                .overlay {
                    LinearGradient(
                        stops: [.init(color: .black.opacity(0), location: 0.35),
                                .init(color: .black.opacity(0.75), location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.8))
                Text(game.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Button(action: play) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)

                    NavigationLink(value: game) {
                        Text("Details")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
            .padding(18)
        }
    }
}
