import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var auth: XboxAuth
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog
    @EnvironmentObject private var rumble: ControllerRumble

    @Binding var showingBrowser: Bool

    @State private var cacheSize = 0
    @State private var showingDiagnostics = false
    @State private var showingSignOut = false
    @State private var refreshingScript = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    account
                    appearance
                    streaming
                    controller
                    storage
                    about
                }
                .padding(.horizontal, Theme.pageInset)
                .padding(.top, 8)
                .padding(.bottom, 36)
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

            Button {
                Task {
                    refreshingScript = true
                    _ = await BetterXCloud.shared.refresh()
                    refreshingScript = false
                }
            } label: {
                HStack {
                    SettingsRowLabel(title: "Update the streaming enhancements",
                                     icon: "arrow.down.circle")
                    if refreshingScript { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(.plain)
            .disabled(refreshingScript)

            Text(BetterXCloud.shared.lastFetched.map {
                "Enhancements updated \($0.formatted(date: .abbreviated, time: .shortened))."
            } ?? "Enhancements have not been downloaded yet.")
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
                    Text(rumble.supportsHaptics
                         ? "Haptics available"
                         : "Haptics unavailable on this controller")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: rumble.controllerName == nil
                      ? "gamecontroller" : "gamecontroller.fill")
                    .foregroundStyle(rumble.controllerName == nil
                                     ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }

            SettingsDivider()

            Toggle("Rumble", isOn: $settings.rumbleEnabled)

            if settings.rumbleEnabled {
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

                Button {
                    rumble.play(left: 0.85, right: 0.85, durationMs: 420, force: true)
                } label: {
                    SettingsRowLabel(title: "Test rumble", icon: "waveform")
                }
                .buttonStyle(.plain)
                .disabled(rumble.controllerName == nil)
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
    @StateObject private var log = AppLog.shared
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
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: log.exportText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share the log")
                }
            }
        }
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
