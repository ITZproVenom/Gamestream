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
                        withAnimation { isLoading = loading }
                    }
                }
            } else {
                signInPrompt
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
                        }
                    }
            }
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.4))
            Text("Sign in to load your library")
                .foregroundStyle(.white.opacity(0.7))
            Button {
                showingSignIn = true
            } label: {
                Text("Sign In")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            ProgressView("Loading library…")
                .tint(.white)
                .foregroundStyle(.white)
        }
    }
}
