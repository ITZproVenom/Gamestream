import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var session: SessionStore
    @State private var isLoading = true
    @State private var showingSignIn = false
    @State private var errorMessage: String?
    @State private var showChrome = true

    var body: some View {
        ZStack {
            if session.isSignedIn {
                ZStack(alignment: .top) {
                    XboxCloudWebView(url: $session.webURL)
                        .ignoresSafeArea()

                    if isLoading {
                        loadingOverlay
                    }

                    if let errorMessage {
                        errorOverlay(errorMessage)
                    }

                    // Floating glass chrome
                    if showChrome && !isLoading {
                        libraryChrome
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .webViewLoadingChanged)) { note in
                    if let loading = note.object as? Bool {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isLoading = loading
                            if loading { errorMessage = nil }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .webViewDidFail)) { note in
                    if let message = note.object as? String {
                        withAnimation {
                            errorMessage = message
                            isLoading = false
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

    // MARK: - Floating chrome

    private var libraryChrome: some View {
        HStack(spacing: 10) {
            Button {
                session.openHome()
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)

            Spacer()

            Text("Xbox Cloud")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())

            Spacer()

            Button {
                session.reloadCurrent()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Sign-in surface

    private var signInSurface: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 52, weight: .medium))
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Your Library")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Sign in with your Xbox account to load games from Xbox Cloud Gaming.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
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

    // MARK: - Overlays

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Loading…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .transition(.opacity)
    }

    private func errorOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                Text("Something went wrong")
                    .font(.headline)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    errorMessage = nil
                    session.reloadCurrent()
                }
                .buttonStyle(.glassProminent)
            }
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }
}
