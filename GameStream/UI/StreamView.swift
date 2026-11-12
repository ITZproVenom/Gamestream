import SwiftUI

/// The player: the Xbox launch page plus an overlay that reports the truth.
struct StreamView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var stream: StreamCoordinator
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rumble: ControllerRumble

    @State private var showingControls = true
    @StateObject private var guardian = SessionGuard.shared
    @State private var hideTask: Task<Void, Never>?
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt = Date()
    @State private var showingStats = false
    @StateObject private var recorder = StreamRecorder.shared

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
    /// The launch sequence, drawn as a manga splash page: halftone paper with
    /// speed lines behind a giant outlined title, the poster in a thick
    /// ink-bordered panel with a hard offset shadow and a rotating starburst
    /// badge, and real progress steps in a speech bubble.
    private func connecting(_ detail: String) -> some View {
        ZStack {
            MangaBackdrop(game: stream.game)

            VStack(spacing: 22) {
                LaunchEmblem(game: stream.game)

                VStack(spacing: 6) {
                    MangaTitle(detail)
                    Text(stageMessage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MangaTheme.ink(scheme).opacity(0.75))
                        .multilineTextAlignment(.center)
                        .animation(.smooth(duration: 0.3), value: stageMessage)
                }

                LaunchSteps(stage: stream.connectStage,
                            title: stream.game?.title ?? "the game")

                HStack(spacing: 16) {
                    Text(Format.clock(elapsed))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(MangaTheme.ink(scheme).opacity(0.6))
                    MangaButton("CANCEL") { stream.exit() }
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


// MARK: - Launch sequence (manga splash page)

/// Ink-and-paper palette for the manga theme: black ink on white paper in
/// light mode, inverted in dark mode.
enum MangaTheme {
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : .black }
    static func paper(_ scheme: ColorScheme) -> Color { scheme == .dark ? .black : .white }
}

/// Halftone paper with radiating speed lines and a giant outlined title —
/// the classic manga splash-page backdrop. The whole field rotates slowly;
/// Reduce Motion freezes it.
struct MangaBackdrop: View {
    let game: Game?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: AppSettings

    private var ink: Color { MangaTheme.ink(scheme) }
    private var paper: Color { MangaTheme.paper(scheme) }

    var body: some View {
        ZStack {
            paper

            if let art = game?.heroURL ?? game?.posterURL {
                GameArtwork(url: art, cornerRadius: 0)
                    .blur(radius: 26)
                    .grayscale(0.7)
                    .opacity(0.22)
            }

            if reduceMotion {
                SpeedField(angle: 0)
                    .opacity(0.9)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    SpeedField(angle: context.date.timeIntervalSince1970 * 6)
                }
                .opacity(0.9)
            }

            Text("PLAY!")
                .font(.system(size: 104, weight: .black, design: .rounded))
                .rotationEffect(.degrees(-8))
                .opacity(0.14)
                .overlay(
                    Text("PLAY!")
                        .font(.system(size: 104, weight: .black, design: .rounded))
                        .foregroundStyle(ink)
                        .rotationEffect(.degrees(-8))
                        .offset(x: 4, y: 4)
                        .opacity(0.14))
                .foregroundStyle(settings.accent.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 70)
        }
        .ignoresSafeArea()
    }

    /// Halftone dots (bigger away from the centre) plus speed lines fanning
    /// out from the middle, drawn in one Canvas and rotated by `angle`.
    private struct SpeedField: View {
        let angle: Double
        @Environment(\.colorScheme) private var scheme
        @EnvironmentObject private var settings: AppSettings

        var body: some View {
            Canvas { ctx, size in
                let ink = MangaTheme.ink(scheme)
                let accent = settings.accent.color
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = hypot(size.width, size.height) / 2

                // speed lines (rotation applied in the angle math itself)
                let rays = 56
                let rot = angle * .pi / 180
                for i in 0..<rays {
                    let a = Double(i) / Double(rays) * .pi * 2 + rot
                    let r0 = maxR * 0.32
                    let r1 = maxR * 1.25
                    var p = Path()
                    p.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
                    p.addLine(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
                    ctx.stroke(p, with: .color(accent.opacity(i % 2 == 0 ? 0.35 : 0.18)),
                               lineWidth: i % 2 == 0 ? 5 : 2)
                }

                // halftone screentone
                let step: CGFloat = 15
                for gy in stride(from: step / 2, to: size.height, by: step) {
                    for gx in stride(from: step / 2, to: size.width, by: step) {
                        let d = hypot(gx - center.x, gy - center.y) / maxR
                        let r = 0.8 + 4.2 * min(d, 1)
                        let dot = Path(ellipseIn: CGRect(x: gx - r, y: gy - r, width: r * 2, height: r * 2))
                        ctx.fill(dot, with: .color(ink.opacity(0.10)))
                    }
                }
            }
        }
    }
}

/// Big bold title with a hard ink outline, manga display style.
struct MangaTitle: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var settings: AppSettings

    init(_ text: String) { self.text = text }

    var body: some View {
        ZStack {
            Text(text)
                .font(.title2.weight(.black).monospaced())
                .foregroundStyle(MangaTheme.ink(scheme))
                .offset(x: 2.5, y: 2.5)
            Text(text)
                .font(.title2.weight(.black).monospaced())
                .foregroundStyle(settings.accent.color)
        }
    }
}
/// The poster in a thick ink-bordered panel with a hard offset shadow
/// (cel-shaded, no blur), slightly tilted, with a rotating starburst badge.
struct LaunchEmblem: View {
    let game: Game?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: AppSettings

    private var ink: Color { MangaTheme.ink(scheme) }
    private var paper: Color { MangaTheme.paper(scheme) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                // hard offset shadow behind the panel
                Rectangle()
                    .fill(ink)
                    .frame(width: 158, height: 208)
                    .offset(x: 8, y: 8)
                Rectangle()
                    .fill(paper)
                    .frame(width: 158, height: 208)
                    .overlay(Rectangle().stroke(ink, lineWidth: 5))
                GameArtwork(url: game?.posterURL ?? game?.heroURL, cornerRadius: 0)
                    .frame(width: 148, height: 198)
            }
            .rotationEffect(.degrees(-3))

            // rotating starburst badge
            ZStack {
                if reduceMotion {
                    Starburst(spikes: 14)
                        .fill(settings.accent.color)
                        .stroke(ink, lineWidth: 3)
                        .frame(width: 86, height: 86)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        Starburst(spikes: 14)
                            .fill(settings.accent.color)
                            .stroke(ink, lineWidth: 3)
                            .frame(width: 86, height: 86)
                            .rotationEffect(.degrees(context.date.timeIntervalSince1970 * 18))
                    }
                }
                Text("GO!")
                    .font(.headline.weight(.black))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(paper, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink, lineWidth: 3))
            }
            .offset(x: 26, y: -20)
        }
    }
}

/// A manga impact star, drawn as a two-radius polygon.
struct Starburst: Shape {
    let spikes: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.62
        let step = .pi / Double(spikes)
        var angle = -Double.pi / 2
        path.move(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        for i in 0..<(spikes * 2) {
            angle += step
            let radius = i % 2 == 0 ? outer : inner
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
        path.closeSubpath()
        return path
    }
}

/// Launch progress drawn as a speech bubble: thick ink border, hard shadow,
/// tail pointing down, bold uppercase rows that tick over as the stream
/// coordinator advances.
struct LaunchSteps: View {
    let stage: StreamCoordinator.ConnectStage
    let title: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: AppSettings

    private var ink: Color { MangaTheme.ink(scheme) }
    private var paper: Color { MangaTheme.paper(scheme) }

    private var rows: [(String, Int)] {
        [("LAUNCH \(title.uppercased())", 0),
         ("CONNECT TO XBOX CLOUD", 1),
         ("START THE SESSION", 2)]
    }

    private var current: Int { min(stage.index, 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    stepIcon(row.1)
                        .frame(width: 20)
                    Text(row.0)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(row.1 < current ? ink.opacity(0.45) : ink)
                        .animation(.smooth(duration: 0.25), value: current)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .padding(.bottom, 8)
        .background(
            ZStack {
                SpeechBubbleShape()
                    .fill(ink)
                    .offset(x: 5, y: 5)
                SpeechBubbleShape()
                    .fill(paper)
                    .stroke(ink, lineWidth: 4)
            })
    }

    @ViewBuilder
    private func stepIcon(_ index: Int) -> some View {
        if index < current {
            ZStack {
                Circle().fill(settings.accent.color).stroke(ink, lineWidth: 3)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.black))
                    .foregroundStyle(ink)
            }
            .frame(width: 20, height: 20)
        } else if index == current {
            if reduceMotion {
                Circle().fill(ink).frame(width: 12, height: 12)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    let s = 1 + 0.4 * (0.5 + 0.5 * sin(context.date.timeIntervalSince1970 * 4))
                    Circle().fill(ink)
                        .frame(width: 12 * CGFloat(s), height: 12 * CGFloat(s))
                        .overlay(Circle().stroke(ink, lineWidth: 2))
                }
            }
        } else {
            Circle().stroke(ink.opacity(0.4), lineWidth: 3)
                .frame(width: 12, height: 12)
        }
    }
}

/// Rounded rectangle with a little tail at the bottom-left, like a manga
/// speech bubble.
struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tailH: CGFloat = 14
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailH)
        path.addPath(Path(roundedRect: body, cornerRadius: 14))
        path.move(to: CGPoint(x: body.minX + 22, y: body.maxY - 1))
        path.addLine(to: CGPoint(x: body.minX + 40, y: body.maxY - 1))
        path.addLine(to: CGPoint(x: body.minX + 18, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A chunky manga button: paper fill, thick ink border, hard offset shadow.
struct MangaButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(MangaTheme.ink(scheme))
                    .offset(x: 4, y: 4)
                RoundedRectangle(cornerRadius: 10)
                    .fill(MangaTheme.paper(scheme))
                    .stroke(MangaTheme.ink(scheme), lineWidth: 3)
                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(MangaTheme.ink(scheme))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
            }
        }
        .buttonStyle(.plain)
    }
}
