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
    @State private var showingStats = false

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
                showingStats = AppSettings.shared.showStreamStats
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

    /// Two clusters on one piece of glass: session controls at the top left,
    /// read-outs and the things that press the site's own buttons at the top
    /// right. The statistics panel is native, driven by WebRTC rather than by
    /// the enhancement script's own overlay.
    private var hud: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    hudButton("Exit", icon: "xmark", id: "exit") { stream.exit() }

                    if !library.queue.isEmpty {
                        hudButton("Next", icon: "forward.end.fill", id: "next") {
                            stream.playNextInQueue()
                        }
                    }

                    hudIcon("arrow.clockwise", label: "Reconnect", id: "reload") {
                        stream.retry()
                    }

                    Spacer(minLength: 0)

                    Text(Format.clock(elapsed))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: Capsule())
                        .glassEffectID("timer", in: glass)

                    if let stats = stream.stats {
                        qualityBadge(stats)
                    }

                    hudIcon("logo.xbox", label: "Xbox guide", id: "guide") {
                        stream.pressGuide()
                    }

                    hudIcon("slider.horizontal.3", label: "Streaming enhancements",
                            id: "enhance") {
                        stream.openEnhancementMenu()
                    }

                    hudIcon(showingStats ? "chart.bar.fill" : "chart.bar",
                            label: showingStats ? "Hide statistics" : "Show statistics",
                            id: "stats", active: showingStats) {
                        withAnimation(.smooth(duration: 0.25)) { showingStats.toggle() }
                    }

                    Image(systemName: rumble.supportsHaptics
                          ? "gamecontroller.fill" : "gamecontroller")
                        .font(.footnote)
                        .foregroundStyle(rumble.controllerName == nil ? .secondary : .primary)
                        .padding(10)
                        .glassEffect(.regular, in: Circle())
                        .glassEffectID("controller", in: glass)
                        .accessibilityLabel(rumble.controllerName ?? "No controller connected")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if showingStats {
                statsPanel
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
    }

    private func hudButton(_ title: String, icon: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 4)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .glassEffectID(id, in: glass)
    }

    private func hudIcon(_ icon: String, label: String, id: String,
                         active: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(active ? Color.accentColor : nil)
        .glassEffectID(id, in: glass)
        .accessibilityLabel(label)
    }

    private func qualityBadge(_ stats: StreamStats) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: stats.quality))
                .frame(width: 7, height: 7)
            Text("\(stats.fps) fps")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: Capsule())
        .glassEffectID("quality", in: glass)
        .accessibilityLabel("\(stats.fps) frames per second")
    }

    /// The statistics panel: the numbers that explain a bad session.
    private var statsPanel: some View {
        let stats = stream.stats ?? StreamStats()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(color(for: stats.quality)).frame(width: 8, height: 8)
                Text(label(for: stats.quality))
                    .font(.footnote.weight(.bold))
                Spacer(minLength: 0)
                if !stats.codec.isEmpty {
                    Text(stats.codec)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: Capsule())
                }
                if !stats.resolution.isEmpty {
                    Text(stats.resolution)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                      spacing: 12) {
                statCell("\(stats.fps)", "FPS")
                statCell(stats.bitrateKbps >= 1000
                         ? String(format: "%.1f", Double(stats.bitrateKbps) / 1000) : "\(stats.bitrateKbps)",
                         stats.bitrateKbps >= 1000 ? "Mbps" : "kbps")
                statCell("\(stats.rttMs)", "Latency ms")
                statCell("\(stats.jitterMs)", "Jitter ms")
                statCell("\(stats.decodeMs)", "Decode ms")
                statCell("\(stats.framesDropped)", "Dropped")
            }
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func statCell(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for quality: StreamStats.Quality) -> Color {
        switch quality {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }

    private func label(for quality: StreamStats.Quality) -> String {
        switch quality {
        case .good: return "Connection looks good"
        case .fair: return "Connection is workable"
        case .poor: return "Connection is struggling"
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
