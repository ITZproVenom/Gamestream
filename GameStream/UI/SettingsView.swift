import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var auth: XboxAuth
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var rumble: ControllerRumble
    @StateObject private var network = NetworkCheck.shared
    @StateObject private var stream = StreamCoordinator.shared
    @StateObject private var guardian = SessionGuard.shared

    @Binding var showingBrowser: Bool

    @State private var cacheSize = 0
    @State private var showingDiagnostics = false
    @State private var showingSignOut = false
    @State private var refreshingScript = false
    @State private var copiedReport = false
    @State private var reinstalled: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    account
                    appearance
                    streaming
                    controller
                    session
                    clips
                    storage
                    about
                }
                .padding(.horizontal, Theme.pageInset)
                .padding(.top, 8)
                .padding(.bottom, 36)
                // The page is exactly as wide as the screen, whatever a
                // child would prefer. Without this one greedy row drags
                // every other row off the right edge with it.
                .containerRelativeFrame(.horizontal)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AuroraBackground() }
            .navigationTitle("Settings")
            .task { await measureCache() }
            .sheet(isPresented: $showingDiagnostics) { DiagnosticsView() }
            .confirmationDialog("Sign out of Xbox?", isPresented: $showingSignOut,
                                titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            } message: {
                Text("This clears the Xbox and Microsoft cookies stored in the app. "
                     + "Your favorites, lists and activity stay.")
            }
        }
    }

    // MARK: - Sections

    private var account: some View {
        SettingsGroup("Account", icon: "person.crop.circle.fill") {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.tint.opacity(0.18)).frame(width: 46, height: 46)
                    Image(systemName: "person.fill").foregroundStyle(.tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.state.gamertag ?? "Signed in")
                        .font(.headline)
                    Text(auth.state.isSignedIn
                         ? "Cloud gaming token present"
                         : "No cloud gaming token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if auth.isChecking { ProgressView().controlSize(.small) }
            }

            SettingsDivider()

            Button {
                Task { await auth.refresh(reason: "settings") }
            } label: {
                SettingsRowLabel(title: "Check session now", icon: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                showingBrowser = true
            } label: {
                SettingsRowLabel(title: "Open xbox.com", icon: "safari")
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                showingSignOut = true
            } label: {
                SettingsRowLabel(title: "Sign out", icon: "rectangle.portrait.and.arrow.right",
                                 destructive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var appearance: some View {
        SettingsGroup("Appearance", icon: "paintbrush.fill") {
            Picker("Theme", selection: $settings.theme) {
                ForEach(AppSettings.Theme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            SettingsDivider()

            VStack(alignment: .leading, spacing: 11) {
                Text("Accent").font(.subheadline.weight(.semibold))
                HStack(spacing: 13) {
                    ForEach(AppSettings.Accent.allCases) { accent in
                        Button {
                            withAnimation(.smooth) { settings.accent = accent }
                        } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if settings.accent == accent {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accent.title)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var streaming: some View {
        SettingsGroup("Streaming", icon: "cloud.fill") {
            Picker("Quality", selection: $settings.quality) {
                ForEach(AppSettings.Quality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }

            SettingsDivider()

            Picker("Region", selection: $settings.region) {
                ForEach(AppSettings.Region.allCases) { region in
                    Text(region.title).tag(region)
                }
            }

            SettingsDivider()

            Toggle("Start the game automatically", isOn: $settings.autoStart)
            SettingsDivider()
            VStack(alignment: .leading, spacing: 5) {
                Toggle("Open the statistics panel with the stream",
                       isOn: $settings.showStreamStats)
                Text("Frame rate, bitrate, latency, jitter, decode time and dropped "
                     + "frames, read from the connection itself. It can also be "
                     + "toggled from the player.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsDivider()
            VStack(alignment: .leading, spacing: 5) {
                Toggle("Match the in-stream menus to GameStream", isOn: $settings.matchStreamStyle)
                Text("Restyles the streaming enhancement's own menus with the app's "
                     + "accent colour, translucency and type. Takes effect the next "
                     + "time a game starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsDivider()
            Toggle("Keep the screen awake", isOn: $settings.keepAwake)
            SettingsDivider()

            HStack {
                Text("Better xCloud").font(.subheadline)
                Spacer()
                Text(BetterXCloud.shared.version.map { "v\($0)" } ?? "not installed")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            Button {
                Task {
                    refreshingScript = true
                    reinstalled = await BetterXCloud.shared.reinstall()
                    refreshingScript = false
                }
            } label: {
                HStack {
                    SettingsRowLabel(title: "Reinstall Better xCloud",
                                     icon: "arrow.trianglehead.2.clockwise")
                    if refreshingScript { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(.plain)
            .disabled(refreshingScript)

            Text(reinstalledMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controller: some View {
        SettingsGroup("Controller", icon: "gamecontroller.fill") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rumble.controllerName ?? "No controller connected")
                        .font(.subheadline.weight(.semibold))
                    Text("Rumble route: \(rumble.path.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: rumble.controllerName == nil
                      ? "gamecontroller" : "gamecontroller.fill")
                    .foregroundStyle(rumble.controllerName == nil
                                     ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }

            Text(rumble.diagnosis.prefix(1).uppercased() + rumble.diagnosis.dropFirst() + ".")
                .font(.caption)
                .foregroundStyle(rumble.path == .unavailable
                                 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)

            SettingsDivider()

            Toggle("Rumble", isOn: $settings.rumbleEnabled)

            if settings.rumbleEnabled {
                SettingsDivider()
                Toggle("Vibrate the phone when the controller cannot",
                       isOn: $settings.phoneRumbleFallback)

                SettingsDivider()
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Intensity").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.1f×", settings.rumbleIntensity))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.rumbleIntensity, in: 0.5...2.5, step: 0.1)
                }

                SettingsDivider()

                switch rumble.testPhase {
                case .waitingForTrigger:
                    HStack(spacing: 10) {
                        Image(systemName: "r.joystick.tilt.up")
                            .foregroundStyle(.tint)
                            .symbolEffect(.pulse)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pull RT on your controller")
                                .font(.subheadline.weight(.semibold))
                            Text("Waiting for a trigger, so the test uses the pad "
                                 + "you are actually holding.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Cancel") { rumble.cancelTest() }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                    }
                case .playing:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Firing…").font(.subheadline.weight(.semibold))
                    }
                case .finished(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            rumble.beginGuidedTest()
                        } label: {
                            SettingsRowLabel(title: "Test again", icon: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                    }
                case .idle:
                    Button {
                        rumble.beginGuidedTest()
                    } label: {
                        SettingsRowLabel(title: "Test rumble", icon: "waveform")
                    }
                    .buttonStyle(.plain)
                }

                SettingsDivider()

                Button {
                    UIPasteboard.general.string = rumble.report
                    copiedReport = true
                } label: {
                    SettingsRowLabel(title: copiedReport ? "Report copied"
                                     : "Copy controller report",
                                     icon: copiedReport ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Everything that governs a running session rather than how it looks.
    private var session: some View {
        SettingsGroup("Session", icon: "timer") {
            Toggle("Rejoin automatically if the stream drops", isOn: $settings.autoReconnect)
            SettingsDivider()

            Toggle("Warn when the connection cannot hold the quality",
                   isOn: $settings.adaptiveQuality)
            SettingsDivider()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Bitrate limit").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(settings.maxBitrateMbps == 0
                         ? "Unlimited" : "\(settings.maxBitrateMbps) Mbps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.maxBitrateMbps) },
                    set: { settings.maxBitrateMbps = Int($0) }
                ), in: 0...15, step: 1)
                Text("Unlimited means Xbox's own maximum of 15 Mbps; there is nothing "
                     + "above that to ask for. A limit is negotiated when a session "
                     + "starts, so it applies to the next game you launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            Toggle("GameStream enhancements", isOn: $settings.enhancerEnabled)
            Text("Our own in-page layer. It edits the session description before the "
                 + "stream is negotiated, which is the only place codec and bitrate "
                 + "are actually decided.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if settings.enhancerEnabled {
                Toggle("Hide the site's touch controls", isOn: $settings.hideTouchControls)

                Toggle("Prefer H.265 when offered", isOn: $settings.preferHEVC)
                Text(stream.offeredCodecs.isEmpty
                     ? "Start a game to see which codecs the server offers."
                     : "Server offered: \(stream.offeredCodecs).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Sharpness").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(settings.sharpness == 0 ? "Off" : "\(settings.sharpness)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.sharpness) },
                        set: { settings.sharpness = Int($0) }
                    ), in: 0...5, step: 1)
                    Text("A real sharpening kernel over the video. It cannot add detail "
                         + "the stream never sent, and high settings make compression "
                         + "blocks more obvious, not less.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Saturation").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(settings.saturation)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.saturation) },
                        set: { settings.saturation = Int($0) }
                    ), in: 50...150, step: 5)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Contrast").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(settings.contrast)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.contrast) },
                        set: { settings.contrast = Int($0) }
                    ), in: 50...150, step: 5)
                }
            }

            SettingsDivider()

            Toggle("Check the connection before starting", isOn: $settings.preflightCheck)
            if let reading = network.latest {
                Text(reading.reachable
                     ? "Last check: \(reading.latencyMs) ms, ±\(reading.spreadMs) ms. \(reading.verdict)"
                     : reading.verdict)
                    .font(.caption)
                    .foregroundStyle(reading.isPoor ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await network.measure() }
            } label: {
                HStack {
                    SettingsRowLabel(title: "Test the connection now", icon: "wifi")
                    if network.isChecking { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(.plain)
            .disabled(network.isChecking)

            SettingsDivider()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Session limit").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(settings.sessionLimitMinutes == 0
                         ? "Off" : "\(settings.sessionLimitMinutes) min")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.sessionLimitMinutes) },
                    set: { settings.sessionLimitMinutes = Int($0) }
                ), in: 0...240, step: 15)
                Text("The game ends itself when the time is up, with warnings at "
                     + "five minutes and one minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            Toggle("Stop if the phone overheats", isOn: $settings.thermalGuard)
            HStack {
                Text("Thermal state").font(.caption)
                Spacer()
                Text(guardian.thermalDescription)
                    .font(.caption)
                    .foregroundStyle(guardian.thermalState == .nominal
                                     ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }

            SettingsDivider()

            Toggle("Warn on low battery", isOn: $settings.batteryGuard)
        }
    }

    private var clips: some View {
        SettingsGroup("Clips", icon: "record.circle") {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Quality").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(settings.recordingBitrateMbps) Mbps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.recordingBitrateMbps) },
                    set: { settings.recordingBitrateMbps = Int($0) }
                ), in: 4...40, step: 2)
                Text("How much detail a recorded clip keeps. Higher costs storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Stop after").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(settings.recordingLimitMinutes) min")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.recordingLimitMinutes) },
                    set: { settings.recordingLimitMinutes = Int($0) }
                ), in: 1...30, step: 1)
                Text("A recording left running cannot fill the device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            VStack(alignment: .leading, spacing: 5) {
                Toggle("Record your voice", isOn: $settings.recordMicrophone)
                Text("Off by default. A clip of a game should not record the room unless asked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storage: some View {
        SettingsGroup("Storage", icon: "internaldrive.fill") {
            HStack {
                Text("Artwork cache").font(.subheadline)
                Spacer()
                Text(Format.bytes(cacheSize))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            Button {
                Task {
                    await PosterCache.shared.clear()
                    await measureCache()
                }
            } label: {
                SettingsRowLabel(title: "Clear artwork cache", icon: "trash")
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                library.clearRecents()
            } label: {
                SettingsRowLabel(title: "Clear recently played", icon: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                library.clearActivity()
            } label: {
                SettingsRowLabel(title: "Clear activity log", icon: "list.bullet.rectangle",
                                 destructive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var about: some View {
        SettingsGroup("About", icon: "info.circle.fill") {
            HStack {
                Text("Version").font(.subheadline)
                Spacer()
                Text(AppInfo.versionLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            HStack {
                Text("Build").font(.subheadline)
                Spacer()
                Text("\(AppInfo.channel) · \(AppInfo.commit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            HStack {
                Text("Device").font(.subheadline)
                Spacer()
                Text(AppInfo.deviceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            Button {
                showingDiagnostics = true
            } label: {
                SettingsRowLabel(title: "Diagnostics", icon: "stethoscope")
            }
            .buttonStyle(.plain)
        }
    }

    /// Says what the reinstall did, rather than only when it last ran.
    private var reinstalledMessage: String {
        if refreshingScript {
            return "Clearing the old copy and its stored settings, then downloading again…"
        }
        if reinstalled == true {
            return "Reinstalled. The stored settings and patch cache were cleared; "
                + "the next game you start uses the fresh copy."
        }
        if reinstalled == false {
            return "The download failed. The previous copy is still in place."
        }
        return BetterXCloud.shared.lastFetched.map {
            "Installed \($0.formatted(date: .abbreviated, time: .shortened)). "
                + "Reinstalling clears its stored settings and patch cache too."
        } ?? "Not downloaded yet. It installs itself the first time you start a game."
    }

    private func measureCache() async {
        cacheSize = await PosterCache.shared.diskUsage()
    }
}

// MARK: - Settings building blocks

/// A titled glass card, which is what replaces the grouped table in 2.0.
struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: Theme.cardShape)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().opacity(0.35)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let icon: String
    var destructive = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(destructive ? Color.red : Color.accentColor)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(destructive ? Color.red : Color.primary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// The log, with everything needed to explain a failure to someone else.
struct DiagnosticsView: View {
    @EnvironmentObject private var auth: XboxAuth
    @EnvironmentObject private var rumble: ControllerRumble
    @StateObject private var log = AppLog.shared
    @StateObject private var network = NetworkCheck.shared
    @StateObject private var stream = StreamCoordinator.shared
    @StateObject private var guardian = SessionGuard.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("State", value: auth.state.isSignedIn ? "Signed in" : "Signed out")
                    if let tag = auth.state.gamertag {
                        LabeledContent("Gamertag", value: tag)
                    }
                    if !auth.tokenSource.isEmpty {
                        LabeledContent("Token source", value: auth.tokenSource)
                    }
                    if !auth.tokenExpires.isEmpty {
                        LabeledContent("Token expires", value: auth.tokenExpires)
                    }
                    if let check = auth.lastCheck {
                        LabeledContent("Last check",
                                       value: check.formatted(date: .omitted, time: .standard))
                    }
                    if let error = auth.lastError {
                        LabeledContent("Last error", value: error)
                    }
                }

                Section("Log") {
                    if log.entries.isEmpty {
                        Text("Nothing logged yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(log.entries.reversed()) { entry in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: entry.level.symbol)
                                    .font(.caption)
                                    .foregroundStyle(color(for: entry.level))
                                Text(entry.line)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground() }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: log.exportText(context: context)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share the log")
                }
            }
        }
    }

    /// What the app was when the log was taken. A shared log that does not
    /// say whether a controller was even connected, or what the connection
    /// measured, leaves the first two questions unanswered.
    private var context: [String] {
        var lines: [String] = []
        lines.append("Session: " + (auth.state.isSignedIn ? "signed in" : "signed out"))
        if !auth.tokenSource.isEmpty { lines.append("Token source: \(auth.tokenSource)") }
        if !auth.tokenExpires.isEmpty { lines.append("Token expires: \(auth.tokenExpires)") }
        if !stream.offeredCodecs.isEmpty { lines.append("Codecs offered: \(stream.offeredCodecs)") }
        lines.append("Controller: " + (rumble.controllerName ?? "none")
                     + (rumble.supportsHaptics ? " with haptics" : " without haptics"))
        if let reading = network.latest { lines.append("Connection: \(reading.detail)") }
        lines.append("Thermal state: \(guardian.thermalDescription)")
        return lines
    }

    private func color(for level: AppLog.Level) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        }
    }
}
