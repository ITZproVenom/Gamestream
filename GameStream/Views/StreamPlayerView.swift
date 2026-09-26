import SwiftUI
import WebKit

/// The player is a real, long-lived browser session dedicated to one game.
///
/// Pressing Play loads the game's launch URL directly. The shared cookie store
/// holds the xbox.com session established by SignInWebView (verified via the
/// strict xbox-session cookie check). Once the game page loads,
/// streamIsolationJS auto-clicks the Play / Play with ads / Resume button so
/// the actual stream starts instead of parking on the game info page.
/// No navigation is ever cancelled — the player behaves like a browser.
struct StreamPlayerView: View {
    @EnvironmentObject var session: SessionStore
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showChrome = false
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var didRecordWebViewCreated = false

    var body: some View {
        ZStack(alignment: .top) {
            XboxCloudWebView(url: $session.webURL)
                .ignoresSafeArea(edges: .all)

            if isLoading {
                PlayLoadingView(title: session.currentGame?.title ?? "")
                    .transition(.opacity)
                    .zIndex(2)
            }

            streamChrome
                .padding(.top, 8)
                .zIndex(3)
        }
        .edgesIgnoringSafeArea(.all)
        .onReceive(NotificationCenter.default.publisher(for: .webViewLoadingChanged)) { note in
            if let loading = note.object as? Bool {
                if isLoading && !loading {
                    SoundManager.playReady()
                    DiagnosticsStore.shared.record(
                        event: "webview_loaded",
                        feature: "stream",
                        gameId: session.currentGame?.id,
                        gameTitle: session.currentGame?.title
                    )
                }
                withAnimation(.easeOut(duration: 0.35)) {
                    isLoading = loading
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerStreamPageReached)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isLoading = false
            }
            scheduleChromeHide(after: 2.5)
        }
        .onReceive(NotificationCenter.default.publisher(for: .webViewDidFail)) { note in
            errorMessage = note.object as? String
            isLoading = false
            DiagnosticsStore.shared.record(
                event: "webview_failed",
                feature: "stream",
                gameId: session.currentGame?.id,
                gameTitle: session.currentGame?.title,
                errorCategory: "webview",
                errorCode: "nav_fail"
            )
            if session.isStreaming {
                DiagnosticsStore.shared.record(
                    event: "streaming_failed",
                    feature: "stream",
                    gameId: session.currentGame?.id,
                    gameTitle: session.currentGame?.title,
                    errorCategory: "webview",
                    errorCode: "nav_fail"
                )
            }
        }
        .onAppear {
            if !didRecordWebViewCreated {
                didRecordWebViewCreated = true
                DiagnosticsStore.shared.record(event: "webview_created", feature: "stream")
            }
        }
        .onDisappear {
            chromeHideTask?.cancel()
            ControllerRumble.shared.teardown()
        }
    }

    private var streamChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showChrome {
                HStack(spacing: 8) {
                    Button {
                        chromeHideTask?.cancel()
                        session.exitStreamToHub()
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

                    Button {
                        chromeHideTask?.cancel()
                        session.returnToHub()
                    } label: {
                        Text("Hub")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Open GameHub")

                    if session.nextQueuedGame != nil {
                        Button {
                            chromeHideTask?.cancel()
                            session.playNextFromStream()
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
            } else if !isLoading {
                Button {
                    revealChrome()
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
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showChrome)
    }

    private func revealChrome() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showChrome = true
        }
        scheduleChromeHide(after: 4.0)
    }

    private func scheduleChromeHide(after seconds: Double) {
        chromeHideTask?.cancel()
        chromeHideTask = Task { @MainActor in
            let ns = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                showChrome = false
            }
        }
    }
}
