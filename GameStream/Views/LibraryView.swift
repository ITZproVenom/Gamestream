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
                .animation(.easeInOut(duration: 0.22), value: session.isStreaming)
                .animation(.easeInOut(duration: 0.22), value: showStreamExit)
                .onReceive(NotificationCenter.default.publisher(for: .webViewLoadingChanged)) { note in
                    if let loading = note.object as? Bool {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
        .sheet(isPresented: $showBetterXCloudInfo) {
            betterXCloudSheet
        }
    }

    private var libraryChrome: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                chromeButton("chevron.left", label: "Back") { session.goBack() }
                chromeButton("house.fill", label: "GameHub") { session.returnToHub() }
            }

            Spacer(minLength: 8)

            if session.currentGame != nil {
                chromeButton(
                    session.currentGame?.isFavorite == true ? "star.fill" : "star",
                    label: session.currentGame?.isFavorite == true ? "Remove favorite" : "Add favorite"
                ) {
                    session.toggleFavoriteCurrent()
                }
            }

            Button {
                showBetterXCloudInfo = true
            } label: {
                Label("Better xCloud", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.glass)
            .fixedSize(horizontal: true, vertical: false)

            chromeButton("arrow.clockwise", label: "Reload") {
                session.reloadCurrent()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func chromeButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
    }

    private var streamExitChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showStreamExit {
                HStack(spacing: 8) {
                    Button {
                        session.exitStreamToHub()
                        showStreamExit = false
                    } label: {
                        Label("Exit", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glass)

                    if session.nextQueuedGame != nil {
                        Button {
                            session.playNextFromStream()
                            showStreamExit = false
                        } label: {
                            Text("Play next")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.glassProminent)
                    }

                    Button {
                        session.returnToHub()
                        showStreamExit = false
                    } label: {
                        Text("Hub")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glass)

                    if session.currentGame != nil {
                        chromeButton(
                            session.currentGame?.isFavorite == true ? "star.fill" : "star",
                            label: session.currentGame?.isFavorite == true ? "Remove favorite" : "Add favorite"
                        ) {
                            session.toggleFavoriteCurrent()
                        }
                    }

                    Spacer(minLength: 0)
                }

                if let title = session.currentGame?.title, !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            } else {
                Button { revealStreamExit() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 32, height: 24)
                }
                .buttonStyle(.glass)
                .opacity(0.65)
                .accessibilityLabel("Show stream controls")
            }
        }
        .padding(.horizontal, 16)
    }

    private func revealStreamExit() {
        streamExitHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            showStreamExit = true
        }
        streamExitHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showStreamExit = false
            }
        }
    }

    private var betterXCloudSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Better xCloud")
                                .font(.headline)
                            Text("Active in your cloud session")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }

                Section("Quick guide") {
                    guideRow("server.rack", "Server & settings", "Use the Better xCloud server/settings control on the Xbox Cloud page.")
                    guideRow("ellipsis.circle", "While playing", "Open the in-game system menu for stream stats, video options and touch controls.")
                    guideRow("arrow.clockwise", "If controls disappear", "Reload the page or leave and re-enter Library to reinject the script.")
                }

                Section("Included") {
                    featureRow("1080p / high quality stream")
                    featureRow("Clarity & visual filters")
                    featureRow("Stream stats")
                    featureRow("Touch controller layouts")
                    featureRow("Remote Play")
                    featureRow("Server / region selection")
                    featureRow("Screenshot capture")
                    featureRow("Volume boost & more")
                }
            }
            .navigationTitle("Better xCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showBetterXCloudInfo = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func guideRow(_ icon: String, _ title: String, _ text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
    }

    private func featureRow(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.primary)
    }

    private var signInSurface: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Xbox Cloud")
                        .font(.system(size: 38, weight: .bold, design: .rounded))

                    Text("Your cloud library, ready when you are.")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text("Sign in with Microsoft to open the full Xbox Cloud Gaming experience and Better xCloud.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showingSignIn = true
                } label: {
                    HStack {
                        Text("Continue with Microsoft")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.glassProminent)

                Text("GameStream uses Microsoft's real sign-in page. Your password is never stored by the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 28)
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading Xbox Cloud")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .transition(.opacity)
    }

    private func errorOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Label("Xbox Cloud couldn't load", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Try again") {
                    errorMessage = nil
                    session.reloadCurrent()
                }
                .buttonStyle(.glassProminent)
            }
            .padding(22)
            .frame(maxWidth: 420, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}
