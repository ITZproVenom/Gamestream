import SwiftUI

/// Shared chrome for the rebuilt Features layer (not the legacy Views).
enum HubFilter: Hashable {
    case home, library, browse, forYou, favorites, recents, lists, activity
    case mode(DiscoveryMode)
    case genre(String)

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .browse: return "Browse"
        case .forYou: return "For You"
        case .favorites: return "Favorites"
        case .recents: return "Recents"
        case .lists: return "Lists"
        case .activity: return "Activity"
        case .mode(let mode): return mode.title
        case .genre(let name): return name
        }
    }
}

struct FeatureChipStyle: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if selected {
                    Capsule().fill(.ultraThinMaterial)
                        .glassEffect(.regular.interactive(), in: Capsule())
                } else {
                    Capsule().fill(.ultraThinMaterial.opacity(0.55))
                        .glassEffect(.regular, in: Capsule())
                }
            }
            .foregroundStyle(selected ? .primary : .secondary)
    }
}

struct FeatureSectionCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.title3.weight(.bold))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct FeatureEmptyCard: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct JumpBackInFeature: View {
    @EnvironmentObject var session: SessionStore
    var onOpen: (CatalogGame) -> Void

    private var items: [CatalogGame] {
        Array(session.recents.prefix(8).map { GameCatalog.catalog(from: $0) })
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Jump back in")
                    .font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { game in
                            Button {
                                session.playCatalogGame(game)
                            } label: {
                                HStack(spacing: 10) {
                                    RemoteImage(url: ArtworkStore.shared.url(for: game.id) ?? game.posterURL) {
                                        Color(hex: game.accent)
                                    }
                                    .frame(width: 44, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        Text(GameCatalog.relativePlayLabel(for: session.recents.first(where: { $0.id == game.id })?.lastSeen ?? Date()))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Image(systemName: "play.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(width: 220, alignment: .leading)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Details") { onOpen(game) }
                                Button(session.isFavorite(game.id) ? "Unfavorite" : "Favorite") {
                                    session.toggleFavorite(game.tracked)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ActivityBannerFeature: View {
    @ObservedObject private var activity = PlayActivityStore.shared
    var onSeeAll: () -> Void

    var body: some View {
        Button(action: onSeeAll) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week · \(PlayActivityStore.format(activity.weekTotal))")
                        .font(.subheadline.weight(.semibold))
                    if let top = activity.mostPlayedThisWeek {
                        Text("Top: \(top.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Stream to build your activity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PlayNextBannerFeature: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        if session.offerPlayNext, let next = session.nextQueuedGame {
            let catalog = GameCatalog.catalog(from: next)
            HStack(spacing: 14) {
                RemoteImage(url: ArtworkStore.shared.url(for: next.id) ?? catalog.posterURL) {
                    Color(hex: catalog.accent)
                }
                .frame(width: 52, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Up next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(catalog.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    session.offerPlayNext = false
                    _ = session.playNextQueued()
                } label: {
                    Text("Play")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
