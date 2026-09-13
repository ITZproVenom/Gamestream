import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Search")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Search games", text: $query)
                    .foregroundStyle(.white)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 60)
    }
}

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            GlassRow(title: "Account", value: session.accountLabel ?? "Not signed in")
            GlassRow(title: "Stream quality", value: "Auto")
            GlassRow(title: "Server region", value: "Auto")

            if session.isSignedIn {
                Button("Sign Out", role: .destructive) {
                    session.signOut()
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }
}

struct GlassRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Text(value).foregroundStyle(.white.opacity(0.5))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
