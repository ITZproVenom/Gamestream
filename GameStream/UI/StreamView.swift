import SwiftUI

/// The player: the Xbox launch page plus an overlay that reports the truth.
struct StreamView: View {
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rumble: ControllerRumble
    @EnvironmentObject private var settings: AppSettings

    @State private var showingControls = true
    @StateObject private var guardian = SessionGuard.shared
    @State private var hideTask: Task<Void, Never>?
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt = Date()
    @State private var showingStats = false
    @StateObject private var recorder = StreamRecorder.shared

    @Namespace private var glass

    var body: some View {
        // While the session is starting the page can be shown as it is, with
        // the app's own loading screen out of the way. Xbox puts dialogs up
        // during a launch - the controller gate, for one - and a loading
        // screen on top of them hides the only thing that can be answered.
        let showSite = settings.showSiteWhileConnecting && stream.phase != .playing

        ZStack {
            Color.black.ignoresSafeArea()

            XboxWebView(role: .stream, url: stream.launchURL,
                        reloadToken: stream.reloadToken)
                .ignoresSafeArea()
                .opacity(stream.phase == .playing || showSite ? 1 : 0.001)
                // Invisible is not the same as inert. While connecting, the
                // page is still there at one thousandth opacity and was
                // still taking touches, so a stray tap pressed something
                // nobody could see.
                .allowsHitTesting(stream.phase == .playing || showSite)

            switch stream.phase {
            case .connecting(let detail):
                if !showSite { connecting(detail) }
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
                        // Eight read-outs do not fit across a phone held in
                        // landscape. The HUD above was already given this
                        // treatment; the strip was still being clipped at the
                        // trailing edge, which hid the codec and resolution.
                        ScrollView(.horizontal) {
                            statsStrip
                        }
                        .scrollIndicators(.visible)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Anything of the app's that is on screen would be recorded, so
        // the recorder is told about all of it and leaves those frames out.
        .onChange(of: overlayShowing, initial: true) { _, showing in
            recorder.setOverlayVisible(showing)
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

    /// The launch sequence: an animated, cinematic loading screen that shows
    /// what is actually happening — the game's art drifting behind a moving
    /// mesh, an orbiting energy ring around the poster, and real progress
    /// steps fed by the stream coordinator.
    private func connecting(_ detail: String) -> some View {
        ZStack {
            LaunchBackdrop(game: stream.game)

            VStack(spacing: 24) {
                LaunchEmblem(game: stream.game)

                VStack(spacing: 6) {
                    Text(detail)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(stageMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .animation(.smooth(duration: 0.3), value: stageMessage)
                }

                LaunchSteps(stage: stream.connectStage,
                            title: stream.game?.title ?? "the game")

                HStack(spacing: 14) {
                    Text(Format.clock(elapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Cancel") { stream.exit() }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .tint(.white)
                }
            }
            .padding(34)
        }
    }

    private var stageMessage: String {
        switch stream.connectStage {
        case .launching: return "Preparing your session…"
        case .connecting: return "Connecting to Xbox Cloud Gaming…"
        case .startingSession: return "Xbox is starting \(stream.game?.title ?? "the game")…"
        }
    }

    private func failure(_ message: String) -> some View {
        GeometryReader { geometry in
            ScrollView {
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
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
            .scrollIndicators(.visible)
        }
    }

    // MARK: - HUD

    /// Two clusters on one piece of glass: session controls at the top left,
    /// read-outs and the things that press the site's own buttons at the top
    /// right. The statistics panel is native, driven by WebRTC rather than by
    /// the enhancement script's own overlay.
    /// True whenever the app is drawing anything over the game.
    private var overlayShowing: Bool {
        stream.phase != .playing || showingControls
            || showingStats || stream.notice != nil
    }

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
                .scrollIndicators(.visible)
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

                    if recorder.isRecording {
                        HStack(spacing: 5) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text(Format.clock(recorder.elapsed))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: Capsule())
                        .glassEffectID("reclock", in: glass)
                    }

                    hudIcon(recorder.isRecording ? "stop.circle.fill" : "record.circle",
                            label: recorder.isRecording ? "Stop recording" : "Record a clip",
                            id: "record", active: recorder.isRecording) {
                        Task {
                            let outcome = await recorder.toggle()
                            stream.show(notice: outcome)
                        }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statsAccessibilityLabel(stats))
    }

    private func statsAccessibilityLabel(_ stats: StreamStats) -> String {
        var parts = [label(for: stats.quality)]
        parts.append("\(stats.fps) frames per second")
        if stats.bitrateKbps >= 1000 {
            parts.append(String(format: "%.1f megabits per second", Double(stats.bitrateKbps) / 1000))
        } else {
            parts.append("\(stats.bitrateKbps) kilobits per second")
        }
        parts.append("\(stats.rttMs) milliseconds round-trip time")
        parts.append("\(stats.jitterMs) milliseconds jitter")
        parts.append("\(stats.decodeMs) milliseconds decode time")
        parts.append("\(stats.framesDropped) frames dropped")
        if !stats.codec.isEmpty { parts.append(stats.codec) }
        if !stats.resolution.isEmpty { parts.append(stats.resolution) }
        return parts.joined(separator: ", ")
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

// MARK: - Launch sequence

/// The animated backdrop behind the launch screen: the game's hero art,
/// blurred and slowly breathing, under a mesh gradient whose points drift
/// over time in the accent colour. Reduce Motion freezes both.
struct LaunchBackdrop: View {
    let game: Game?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            Color.black

            if let art = game?.heroURL ?? game?.posterURL {
                if reduceMotion {
                    GameArtwork(url: art, cornerRadius: 0)
                        .blur(radius: 64)
                        .scaleEffect(1.15)
                        .overlay(Color.black.opacity(0.2))
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let t = context.date.timeIntervalSince1970
                        let s = 1.12 + 0.05 * CGFloat(sin(t * 0.45))
                        GameArtwork(url: art, cornerRadius: 0)
                            .blur(radius: 64)
                            .scaleEffect(s)
                            .offset(x: 14 * CGFloat(sin(t * 0.3)), y: 10 * CGFloat(cos(t * 0.23)))
                            .overlay(Color.black.opacity(0.2))
                    }
                }
            }

            if reduceMotion {
                MeshGradient(width: 3, height: 3, points: Self.midPoints, colors: mesh)
                    .opacity(0.5)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    MeshGradient(width: 3, height: 3,
                                 points: Self.driftingPoints(context.date.timeIntervalSince1970),
                                 colors: mesh)
                }
                .opacity(0.5)
            }

            LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.25), .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var mesh: [Color] {
        let accent = settings.accent.color
        return [
            accent.opacity(0.6), accent.opacity(0.25), Color.black,
            accent.opacity(0.35), Color.black.opacity(0.75), accent.opacity(0.45),
            Color.black, accent.opacity(0.22), Color.black.opacity(0.9)
        ]
    }

    private static func driftingPoints(_ t: TimeInterval) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.7)), b = Float(cos(t * 0.5)), c = Float(sin(t * 0.9 + 1.7))
        return [
            .init(0, 0), .init(0.5 + 0.12 * a, 0), .init(1, 0),
            .init(0, 0.5), .init(0.5 + 0.10 * b, 0.5 + 0.06 * c), .init(1, 0.5),
            .init(0, 1), .init(0.5 - 0.12 * c, 1), .init(1, 1)
        ]
    }

    private static let midPoints: [SIMD2<Float>] = [
        .init(0, 0), .init(0.55, 0), .init(1, 0),
        .init(0, 0.5), .init(0.5, 0.55), .init(1, 0.5),
        .init(0, 1), .init(0.45, 1), .init(1, 1)
    ]
}

/// The poster at the centre of the launch screen, wrapped in an orbiting
/// energy ring with a pulsing glow behind it.
struct LaunchEmblem: View {
    let game: Game?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            if reduceMotion {
                Circle()
                    .fill(settings.accent.color.opacity(0.32))
                    .blur(radius: 46)
                    .frame(width: 190, height: 190)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let s = 1 + 0.07 * sin(context.date.timeIntervalSince1970 * 2.2)
                    Circle()
                        .fill(settings.accent.color.opacity(0.32))
                        .blur(radius: 46)
                        .frame(width: 190 * CGFloat(s), height: 190 * CGFloat(s))
                }
            }

            ZStack {
                if reduceMotion {
                    Circle()
                        .stroke(settings.accent.color.opacity(0.85), lineWidth: 3)
                        .frame(width: 178, height: 178)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                        let angle = context.date.timeIntervalSince1970 * 100
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(
                                AngularGradient(
                                    colors: [settings.accent.color, .clear,
                                             settings.accent.color.opacity(0.5), .clear],
                                    center: .center,
                                    startAngle: .degrees(angle),
                                    endAngle: .degrees(angle + 300)),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 178, height: 178)
                    }
                }

                GameArtwork(url: game?.posterURL ?? game?.heroURL, cornerRadius: 22)
                    .frame(width: 118, height: 158)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: settings.accent.color.opacity(0.5), radius: 24, y: 8)
            }
        }
    }
}

/// Real launch progress as a checklist: each row ticks over as the stream
/// coordinator advances, and the current row pulses.
struct LaunchSteps: View {
    let stage: StreamCoordinator.ConnectStage
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [(String, Int)] {
        [("Launch \(title)", 0),
         ("Connect to Xbox Cloud Gaming", 1),
         ("Start the stream session", 2)]
    }

    private var current: Int { min(stage.index, 2) }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    stepIcon(row.1)
                        .frame(width: 18)
                    Text(row.0)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(row.1 < current ? .white.opacity(0.5) : .white)
                        .animation(.smooth(duration: 0.25), value: current)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func stepIcon(_ index: Int) -> some View {
        if index < current {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if index == current {
            if reduceMotion {
                Circle().fill(.white).frame(width: 10, height: 10)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    let s = 1 + 0.35 * (0.5 + 0.5 * sin(context.date.timeIntervalSince1970 * 4))
                    Circle().fill(.white)
                        .frame(width: 10 * CGFloat(s), height: 10 * CGFloat(s))
                }
            }
        } else {
            Circle().stroke(.white.opacity(0.35), lineWidth: 2)
                .frame(width: 10, height: 10)
        }
    }
}
