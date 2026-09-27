import SwiftUI

/// The player: the Xbox launch page plus an overlay that reports the truth.
struct StreamView: View {
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rumble: ControllerRumble

    @State private var showingControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt = Date()

    @Namespace private var glass

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            XboxWebView(role: .stream, url: stream.launchURL,
                        reloadToken: stream.reloadToken)
                .ignoresSafeArea()
                .opacity(stream.phase == .playing ? 1 : 0.001)

            switch stream.phase {
            case .connecting(let detail):
                connecting(detail)
            case .failed(let message):
                failure(message)
            case .playing, .idle:
                EmptyView()
            }

            if stream.phase == .playing, showingControls {
                hud.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .statusBarHidden(stream.phase == .playing)
        .persistentSystemOverlays(stream.phase == .playing ? .hidden : .automatic)
        .contentShape(Rectangle())
        .onTapGesture {
            guard stream.phase == .playing else { return }
            withAnimation(.smooth(duration: 0.25)) { showingControls.toggle() }
            if showingControls { scheduleHide() }
        }
        .onChange(of: stream.phase) { _, phase in
            if phase == .playing {
                startedAt = Date()
                scheduleHide()
            }
        }
        .task(id: stream.phase == .playing) {
            guard stream.phase == .playing else { return }
            // A visible session timer, ticking once a second and no faster.
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: - States

    private func connecting(_ detail: String) -> some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large).tint(.white)
            Text(detail)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Connecting to Xbox Cloud Gaming")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
            Button("Cancel") { stream.exit() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .padding(.top, 4)
        }
        .padding(34)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("The stream stopped")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Close") { stream.exit() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .tint(.white)
                Button("Try again") { stream.retry() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            }
            .padding(.top, 6)
        }
        .padding(34)
        .frame(maxWidth: 460)
    }

    // MARK: - HUD

    private var hud: some View {
        VStack {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        stream.exit()
                    } label: {
                        Label("Exit", systemImage: "xmark")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .glassEffectID("exit", in: glass)

                    if !library.queue.isEmpty {
                        Button {
                            stream.playNextInQueue()
                        } label: {
                            Label("Next", systemImage: "forward.end.fill")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .glassEffectID("next", in: glass)
                    }

                    Button {
                        stream.retry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .glassEffectID("reload", in: glass)
                    .accessibilityLabel("Reconnect")

                    Spacer(minLength: 0)

                    Text(Format.clock(elapsed))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: Capsule())
                        .glassEffectID("timer", in: glass)

                    if !stream.resolution.isEmpty {
                        Text(stream.resolution)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: Capsule())
                            .glassEffectID("resolution", in: glass)
                    }

                    Image(systemName: rumble.supportsHaptics
                          ? "gamecontroller.fill" : "gamecontroller")
                        .font(.footnote)
                        .foregroundStyle(rumble.controllerName == nil ? .secondary : .primary)
                        .padding(9)
                        .glassEffect(.regular, in: Circle())
                        .glassEffectID("controller", in: glass)
                        .accessibilityLabel(rumble.controllerName ?? "No controller connected")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()
        }
    }

    /// The overlay is a visitor, not a fixture: it gets out of the way.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { showingControls = false }
        }
    }
}
