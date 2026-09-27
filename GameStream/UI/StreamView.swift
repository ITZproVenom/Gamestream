import SwiftUI

/// The player: the Xbox launch page plus an overlay that reports the truth.
struct StreamView: View {
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rumble: ControllerRumble

    @State private var showingControls = true
    @State private var hideTask: Task<Void, Never>?

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
                controls.transition(.opacity)
            }
        }
        .statusBarHidden(stream.phase == .playing)
        .persistentSystemOverlays(stream.phase == .playing ? .hidden : .automatic)
        .contentShape(Rectangle())
        .onTapGesture {
            guard stream.phase == .playing else { return }
            withAnimation(.easeOut(duration: 0.2)) { showingControls.toggle() }
            if showingControls { scheduleHide() }
        }
        .onChange(of: stream.phase) { _, phase in
            if phase == .playing { scheduleHide() }
        }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: - States

    private func connecting(_ detail: String) -> some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(.white)
            Text(detail)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Connecting to Xbox Cloud Gaming")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
            Button("Cancel") { stream.exit() }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(.top, 6)
        }
        .padding(30)
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
                    .buttonStyle(.bordered)
                    .tint(.white)
                Button("Try again") { stream.retry() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .padding(34)
        .frame(maxWidth: 460)
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 10) {
                Button {
                    stream.exit()
                } label: {
                    Label("Exit", systemImage: "xmark")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(.black.opacity(0.55), in: Capsule())

                if !library.queue.isEmpty {
                    Button {
                        stream.playNextInQueue()
                    } label: {
                        Label("Next", systemImage: "forward.end.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.55), in: Capsule())
                }

                Spacer()

                if !stream.resolution.isEmpty {
                    Text(stream.resolution)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.5), in: Capsule())
                }

                Image(systemName: rumble.supportsHaptics
                      ? "gamecontroller.fill" : "gamecontroller")
                    .font(.footnote)
                    .foregroundStyle(rumble.controllerName == nil
                                     ? .white.opacity(0.4) : .white)
                    .padding(9)
                    .background(.black.opacity(0.5), in: Circle())
                    .accessibilityLabel(rumble.controllerName ?? "No controller connected")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()
        }
    }

    /// The overlay is a visitor, not a fixture: it gets out of the way.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showingControls = false }
        }
    }
}
