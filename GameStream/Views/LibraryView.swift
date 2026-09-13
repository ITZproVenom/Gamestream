import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var session: SessionStore
    @State private var isLoading = true
    @State private var showingSignIn = false

    var body: some View {
        ZStack {
            if session.isSignedIn {
                ZStack {
                    XboxCloudWebView()
                        .ignoresSafeArea()

                    if isLoading {
                        loadingOverlay
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .webViewLoadingChanged)) { note in
                    if let loading = note.object as? Bool {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isLoading = loading
                        }
                    }
                }
            } else {
                signInSurface
            }
        }
        .sheet(isPresented: $showingSignIn) {
            NavigationStack {
                SignInWebView()
                    .navigationTitle("Sign in")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                session.markSignedIn()
                                showingSignIn = false
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sign-in surface (native Liquid Glass)

    private var signInSurface: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 52, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)

                VStack(spacing: 8) {
                    Text("Your Library")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Sign in with your Xbox account to load games from Xbox Cloud Gaming.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }
            }
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 28)

            Button {
                showingSignIn = true
            } label: {
                Text("Sign In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Loading library…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .transition(.opacity)
    }
}
