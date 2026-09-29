import SwiftUI

/// The player: the Xbox launch page plus an overlay that reports the truth.
struct StreamView: View {
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rumble: ControllerRumble

    @State private var showingControls = true
    @StateObject private var guardian = SessionGuard.shared
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
                // Invisible is not the same as inert. While connecting, the
                // page is still there at one thousandth opacity and was
                // still taking touches, so a stray tap pressed something
                // nobody could see.
                .allowsHitTesting(stream.phase == .playing)

            switch stream.phase {
            case .connecting(let detail):
                connecting(detail)
            case .failed(let message):
                failure(message)
            case .playing, .idle:
                EmptyView()
            }

            if stream.phase == .playing {
                // The controls hide themselves after a few seconds. The
                // statistics used to be inside them and went with them, so
                // the button that turned them on looked like it did nothing.
                // They are their own layer now and stay until turned off.
                VStack(spacing: 10) {
                    if showingControls {
                        hud.transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if showingStats {
                        statsStrip
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
            }

            // A guaranteed way back to the overlay. The page owns the touches
            // over the video, so there has to be something that is always
            // present and unambiguously ours.
            if stream.phase == .playing, !showingControls {
                VStack {
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { showingControls = true }
                        scheduleHide()
                    } label: {
                        Capsule()
                            .fill(.white.opacity(0.28))
                            .frame(width: 46, height: 5)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show the GameStream controls")
                    Spacer()
                }
                .transition(.opacity)
            }

            if let notice = stream.notice {
                VStack {
                    Spacer()
                    Text(notice)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .padding(.bottom, 26)
                        .padding(.horizontal, 20)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: stream.notice)
        .statusBarHidden(stream.phase == .playing)
        .persistentSystemOverlays(stream.phase == .playing ? .hidden : .automatic)
        // There is deliberately no tap gesture over the whole view.
        //
        // A tap recogniser on the container cancels the touches it observes
        // in the view underneath once it fires, so a single tap never
        // reached the page: the enhancement menu could be opened and seen
        // but nothing in it could be pressed, and the site's own on-screen
        // buttons were dead while the thumbstick, being a drag, still
        // worked. The controls hide themselves on a timer and the grab
        // handle above brings them back.
        .onChange(of: stream.overlayRequest) { _, _ in
            withAnimation(.smooth(duration: 0.25)) { showingControls = true }
            scheduleHide()
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
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                hudSessionControls

                // Fourteen controls do not fit across a phone held in
                // landscape, and the last of them was being cut off by the
                // edge of the screen. They scroll now instead of falling off
                // it, anchored to the trailing edge so the buttons stay put
                // and the read-outs are what slide away.
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        hudReadouts
                    }
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// Ending, skipping and reconnecting. These never scroll away.
    @ViewBuilder
    private var hudSessionControls: some View {
                    hudButton("Exit", icon: "xmark", id: "exit") { stream.exit() }

                    if !library.queue.isEmpty {
                        hudButton("Next", icon: "forward.end.fill", id: "next") {
                            stream.playNextInQueue()
                        }
                    }

                    hudIcon("arrow.clockwise", label: "Reconnect", id: "reload") {
                        stream.retry()
                    }
    }

    /// Read-outs and the controls that press the site's own buttons.
    @ViewBuilder
    private var hudReadouts: some View {
                    Text(Format.clock(elapsed))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: Capsule())
                        .glassEffectID("timer", in: glass)

                    if let remaining = guardian.remaining {
                        Text("−\(Format.clock(remaining))")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(remaining < 300 ? .orange : .secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .glassEffect(.regular, in: Capsule())
                            .glassEffectID("limit", in: glass)
                    }

                    if let stats = stream.stats {
                        qualityBadge(stats)
                    }

                    hudIcon("logo.xbox", label: "Xbox guide", id: "guide") {
                        stream.pressGuide()
                    }

                    hudIcon("slider.horizontal.3",
                            label: stream.enhancementMenuOpen
                            ? "Close enhancements" : "Streaming enhancements",
                            id: "enhance",
                            active: stream.enhancementMenuOpen) {
                        stream.toggleEnhancementMenu()
                    }

                    hudIcon("camera.fill", label: "Screenshot", id: "shot") {
                        Task {
                            let outcome = await StreamCapture.capture()
                            stream.show(notice: outcome.message)
                        }
                    }

                    hudIcon("power", label: "Quit the game", id: "quit") {
                        stream.quitGame()
                    }

                    hudIcon(showingStats ? "chart.bar.fill" : "chart.bar",
                            label: showingStats ? "Hide statistics" : "Show statistics",
                            id: "stats", active: showingStats) {
                        withAnimation(.smooth(duration: 0.25)) { showingStats.toggle() }
                    }

                    // This was a plain image, so pressing it did nothing.
                    // It reports what is connected and how rumble is being
                    // delivered, and gives the pad a nudge so the answer can
                    // be felt rather than just read.
                    hudIcon(rumble.supportsHaptics ? "gamecontroller.fill" : "gamecontroller",
                            label: rumble.controllerName ?? "No controller connected",
                            id: "controller") {
                        stream.show(notice: controllerSummary)
                        _ = rumble.play(left: 0.7, right: 0.7, durationMs: 450)
                    }
    }

    private func hudButton(_ title: String, icon: String, id: String,
                           action: @escaping () -> Void) -> some View {
        // Every press restarts the four second timer. Without this the
        // controls could vanish underneath a finger halfway through using
        // them, which read as the button having failed.
        Button { action(); scheduleHide() } label: {
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
        Button { action(); scheduleHide() } label: {
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
    /// One line rather than a card.
    ///
    /// The old panel was a six-cell grid that covered a good part of the
    /// picture, which is the opposite of what a read-out during a game is
    /// for. Everything it said still fits on one strip.
    private var statsStrip: some View {
        let stats = stream.stats ?? StreamStats()
        let mbps = Double(stats.bitrateKbps) / 1000
        return HStack(spacing: 10) {
            Circle()
                .fill(color(for: stats.quality))
                .frame(width: 7, height: 7)

            statChip("\(stats.fps)", "fps")
            if stats.bitrateKbps >= 1000 {
                statChip(String(format: "%.1f", mbps), "Mbps")
            } else {
                statChip("\(stats.bitrateKbps)", "kbps")
            }
            statChip("\(stats.rttMs)", "ms")
            statChip("\(stats.jitterMs)", "jitter")
            statChip("\(stats.decodeMs)", "decode")
            statChip("\(stats.framesDropped)", "dropped")

            if !stats.codec.isEmpty {
                Text(stats.codec)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if !stats.resolution.isEmpty {
                Text(stats.resolution)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label(for: stats.quality))
    }

    private func statChip(_ value: String, _ caption: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// What is connected and how rumble is reaching it.
    private var controllerSummary: String {
        guard let name = rumble.controllerName else {
            return "No controller connected"
        }
        return "\(name) - \(rumble.path.title)"
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
