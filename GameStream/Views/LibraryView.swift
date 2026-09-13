import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var session: SessionStore
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if session.library.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(session.library) { game in
                            NavigationLink {
                                StreamPlayerView(game: game)
                            } label: {
                                GlassGameCard(game: game)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 120)
        }
    }

    private var header: some View {
        Text("Library")
            .font(.largeTitle.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.4))
            Text(session.isSignedIn ? "No games found yet." : "Sign in to load your library.")
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

struct GlassGameCard: View {
    let game: GameEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.08))
                .aspectRatio(3/4, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )

            Text(game.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
