import SwiftUI

struct SearchView: View {
    var body: some View {
        XboxCloudWebView()
            .ignoresSafeArea()
    }
}

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @AppStorage("streamQuality") private var streamQuality = "Auto"
    @AppStorage("serverRegion") private var serverRegion = "Auto"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            GlassRow(title: "Account", value: session.accountLabel ?? "Not signed in")
            GlassRow(title: "Stream quality", value: streamQuality)
            GlassRow(title: "Server region", value: serverRegion)

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
