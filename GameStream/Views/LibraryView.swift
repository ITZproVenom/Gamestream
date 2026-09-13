import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var session: SessionStore
    @State private var isLoading = true
    @State private var showingSignIn = false
    @State private var errorMessage: String?
    @State private var showBetterXCloudInfo = false
    @State private var showStreamExit = false
    @State private var streamExitHideTask: Task<Void, Never>?

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

                    if session.isStreaming && !isLoading {
                        streamExitChrome
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if !session.isStreaming && !isLoading {
                        libraryChrome
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: session.isStreaming)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showStreamExit)
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
                .onChange(of: session.isStreaming) { _, streaming in
                    if !streaming {
                        showStreamExit = false
                        streamExitHideTask?.cancel()
                    }
                }
            } else {
                signInSurface
            }
        }
        .sheet(isPresented: $showingSignIn) {
            NavigationStack {
                SignInWebView()
                    .navigationTitle("Microsoft account")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingSignIn = false
                            }
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
        .sheet(isPresented: $showBetterXCloudInfo) {
            betterXCloudSheet
        }
    }

    private var libraryChrome: some View {
        HStack(spacing: 6) {
            Button {
                session.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Back")

            Button {
                session.returnToHub()
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("GameHub")

            Spacer(minLength: 4)

            Button {
                showBetterXCloudInfo = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Better xCloud")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
            .buttonStyle(.glass)
            .fixedSize(horizontal: true, vertical: false)

            if session.currentGame != nil {
                Button {
                    session.toggleFavoriteCurrent()
                } label: {
                    Image(systemName: session.currentGame?.isFavorite == true ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(session.currentGame?.isFavorite == true ? "Remove favorite" : "Add favorite")
            }

            Button {
                session.reloadCurrent()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Reload")
        }
        .padding(.horizontal, 12)
    }

    private var streamExitChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showStreamExit {
                HStack(spacing: 8) {
                    Button {
                        session.exitStreamToHub()
                        showStreamExit = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Exit")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Exit stream")

                    if session.nextQueuedGame != nil {
                        Button {
                            session.playNextFromStream()
                            showStreamExit = false
                        } label: {
                            Text("Play next")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Play next queued game")
                    }

                    Button {
                        session.returnToHub()
                        showStreamExit = false
                    } label: {
                        Text("Hub")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Open GameHub")

                    if session.currentGame != nil {
                        Button {
                            session.toggleFavoriteCurrent()
                        } label: {
                            Image(systemName: session.currentGame?.isFavorite == true ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 32, height: 28)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(session.currentGame?.isFavorite == true ? "Remove favorite" : "Add favorite")
                    }
                    Spacer(minLength: 0)
                }
                if let title = session.currentGame?.title, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 4)
                }
            } else {
                Button {
                    revealStreamExit()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.glass)
                .opacity(0.55)
                .accessibilityLabel("Show stream controls")
            }
        }
        .padding(.horizontal, 16)
    }

    private func revealStreamExit() {
        streamExitHideTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showStreamExit = true
        }
        streamExitHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                showStreamExit = false
            }
        }
    }

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
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Text("All features run inside the stream")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to open the full menu")
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

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
                    .fixedSize(horizontal: false, vertical: true)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var signInSurface: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 52, weight: .medium))
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("GameStream")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("Sign in with Microsoft to load GameHub and Xbox Cloud Gaming.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 28)

            Button {
                showingSignIn = true
            } label: {
                Text("Sign in with Microsoft")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

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
                    .lineLimit(1)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

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
