import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var session: SessionStore
    @State private var isLoading = true
    @State private var showingSignIn = false
    @State private var errorMessage: String?
    @State private var showBetterXCloudInfo = false

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

                    // Hide floating chrome while streaming a game
                    if !session.isStreaming && !isLoading {
                        libraryChrome
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: session.isStreaming)
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
        .sheet(isPresented: $showBetterXCloudInfo) {
            betterXCloudSheet
        }
    }

    // MARK: - Floating chrome

    private var libraryChrome: some View {
        HStack(spacing: 10) {
            Button {
                session.openHome()
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)

            Spacer()

            Button {
                showBetterXCloudInfo = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Better xCloud")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .buttonStyle(.glass)

            Spacer()

            Button {
                session.reloadCurrent()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Better xCloud sheet

    private var betterXCloudSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Better xCloud is active")
                                .font(.headline)
                            Text("All features run inside the stream")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to open the full menu")
                            .font(.title3.weight(.semibold))

                        tipRow(icon: "server.rack", title: "Server / settings button",
                               text: "On the Xbox Cloud page, look near your profile picture for the server/region button added by Better xCloud. Tap it to open the full settings menu.")

                        tipRow(icon: "ellipsis.circle", title: "While playing",
                               text: "Open the in-game system menu (…) to access Stream Stats, video options, touch controls and more.")

                        tipRow(icon: "arrow.clockwise", title: "If the menu is missing",
                               text: "Tap the refresh button in the top bar, or leave and re-enter Library. The script is re-injected on every load.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Included features")
                            .font(.title3.weight(.semibold))

                        featureChip("1080p / High quality stream")
                        featureChip("Clarity & visual filters")
                        featureChip("Stream stats overlay")
                        featureChip("Touch controller layouts")
                        featureChip("Remote Play")
                        featureChip("Server / region selection")
                        featureChip("Screenshot capture")
                        featureChip("Volume boost & more")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Better xCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showBetterXCloudInfo = false }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func tipRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func featureChip(_ title: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(title)
                .font(.subheadline)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sign-in

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
