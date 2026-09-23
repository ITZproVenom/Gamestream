import SwiftUI

struct SearchFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var catalogLive = CatalogLiveStore.shared
    @State private var query: String = ""
    var onOpenGame: (CatalogGame) -> Void

    private var results: [CatalogGame] {
        _ = catalogLive.revision
        return GameCatalog.matches(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search games", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    session.openCloudSearch(query: query)
                } label: {
                    Label("Search Xbox Cloud", systemImage: "cloud")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(results.prefix(40)) { game in
                        HStack(spacing: 12) {
                            Button {
                                onOpenGame(game)
                            } label: {
                                HStack(spacing: 12) {
                                    posterThumb(game)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.title)
                                            .font(.body.weight(.semibold))
                                            .lineLimit(1)
                                        Text(game.genre)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                session.playCatalogGame(game)
                            } label: {
                                Text("Play")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.glassProminent)
                        }
                        .padding(12)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func posterThumb(_ game: CatalogGame) -> some View {
        RemoteImage(url: ArtworkStore.shared.url(for: game.id) ?? game.posterURL) {
            Color(hex: game.accent)
        }
        .frame(width: 48, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
