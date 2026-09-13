import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var session: SessionStore
    @State private var showingSignIn = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 18) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)

                    Text("GameStream")
                        .font(.system(size: sizeClass == .compact ? 36 : 42, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("Welcome")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("Sign in with Microsoft to open GameHub, stream Xbox Cloud games, and use Better xCloud.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(28)
                .frame(maxWidth: 560)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 24)

                Button {
                    showingSignIn = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.body.weight(.semibold))
                        Text("Sign in with Microsoft")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 32)
                .padding(.top, 22)
                .frame(maxWidth: 520)
                .accessibilityLabel("Sign in with Microsoft")

                Text("Uses Microsoft's real sign-in page. GameStream never stores your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)

                Spacer(minLength: 32)
            }
        }
        .sheet(isPresented: $showingSignIn) {
            NavigationStack {
                SignInWebView()
                    .navigationTitle("Microsoft account")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingSignIn = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .environmentObject(session)
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn { showingSignIn = false }
        }
    }
}
