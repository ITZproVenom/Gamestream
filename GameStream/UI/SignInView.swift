import SwiftUI

/// The sign-in surface: Microsoft's own page, unmodified.
///
/// GameStream does not build a login URL and does not inject anything here.
/// 1.x constructed a legacy `login.srf?wp=MBI_SSL` request and then declared
/// success when a cookie with a familiar-looking name appeared. Those cookies
/// are not what xbox.com/play streams with, which is why sign-in appeared to
/// work and then the player asked the user to sign in again. Letting the site
/// run its own flow produces the tokens the cloud service actually checks.
struct SignInView: View {
    @EnvironmentObject private var auth: XboxAuth
    @Environment(\.dismiss) private var dismiss

    @State private var reloadToken = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                XboxWebView(role: .signIn, url: XboxAuth.playURL, reloadToken: reloadToken)
                    .ignoresSafeArea(edges: .bottom)

                statusBar
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        reloadToken &+= 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload the page")
                }
            }
            .task {
                auth.beginWatching()
                await auth.refresh(reason: "sign-in opened")
            }
            .onDisappear { auth.endWatching() }
            .onChange(of: auth.state) { _, state in
                // Close the moment a real streaming token exists, so nobody has
                // to guess whether the sign-in "took".
                if state.isSignedIn { dismiss() }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 11) {
            if auth.state.isSignedIn {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(auth.state.isSignedIn ? "Signed in" : "Waiting for Xbox sign-in")
                    .font(.footnote.weight(.semibold))
                Text(auth.state.isSignedIn
                     ? "Cloud gaming is ready."
                     : "Finish signing in above. This closes itself when Xbox is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Check") {
                Task { await auth.refresh(reason: "manual check") }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

/// Shown instead of the app when there is no usable Xbox session.
struct WelcomeView: View {
    @EnvironmentObject private var auth: XboxAuth
    @State private var showingSignIn = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.28), Color(uiColor: .systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                Spacer()

                Image(systemName: "cloud.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 9) {
                    Text("GameStream")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("Xbox Cloud Gaming, without the clutter.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("Sign in with your Microsoft account to play the games included "
                     + "with Xbox Game Pass Ultimate. The sign-in page is Microsoft's own.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showingSignIn = true
                } label: {
                    HStack {
                        Text("Continue with Microsoft").font(.headline)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if case .checking = auth.state {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking your Xbox session…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 28)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView().environmentObject(auth)
        }
    }
}
