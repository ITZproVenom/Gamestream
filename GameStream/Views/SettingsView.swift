import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var activity = PlayActivityStore.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @ObservedObject private var controller = ControllerManager.shared

    @State private var keepAwake = false
    @State private var resumeOnOpen = false
    @State private var resolution: String = SessionStore.storedResolution
    @State private var region: String = SessionStore.storedRegion
    @State private var photoItem: PhotosPickerItem?
    @State private var testPulseNote = ""

    var isActive: Bool = true

    private let resolutions = ["Auto", "720p", "1080p", "1080p HQ"]
    private let regions = ["Auto", "North America", "Europe", "Asia", "Australia"]

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.0"
    }

    private var rumbleIntensityLabel: String {
        let v = appearance.controllerRumbleIntensity
        if v < 0.85 { return "Light" }
        if v < 1.35 { return "Normal" }
        if v < 2.0 { return "Strong" }
        if v < 2.6 { return "Heavy" }
        return "Max"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                pageHeader

                settingsSection("Account") {
                    settingRow(icon: "person.crop.circle", title: "Microsoft account") {
                        Text(session.accountLabel ?? "Not signed in")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                settingsSection("Appearance") {
                    menuRow("Theme", icon: "circle.lefthalf.filled", value: appearance.mode.title) {
                        ForEach(AppAppearanceMode.allCases, id: \.self) { option in
                            Button(option.title) { appearance.mode = option }
                        }
                    }
                    divider
                    menuRow("Accent", icon: "paintpalette", value: appearance.accent.title) {
                        ForEach(AccentTheme.allCases, id: \.self) { option in
                            Button(option.title) { appearance.accent = option }
                        }
                    }
                    divider
                    menuRow("Background", icon: "rectangle.on.rectangle", value: appearance.backgroundStyle.title) {
                        ForEach(BackgroundStyle.allCases, id: \.self) { option in
                            Button(option.title) { appearance.backgroundStyle = option }
                        }
                    }

                    if appearance.backgroundStyle == .customColor {
                        divider
                        menuRow("Color", icon: "circle.fill", value: appearance.customBgColor.title) {
                            ForEach(CustomBgColor.allCases, id: \.self) { option in
                                Button(option.title) { appearance.customBgColor = option }
                            }
                        }
                    }

                    if appearance.backgroundStyle == .customPhoto {
                        divider
                        VStack(alignment: .leading, spacing: 12) {
                            if let image = appearance.customBackgroundImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 120)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            HStack {
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    Label(
                                        appearance.customBackgroundImage == nil ? "Choose photo" : "Change photo",
                                        systemImage: "photo"
                                    )
                                    .font(.subheadline.weight(.medium))
                                }
                                .buttonStyle(.glass)

                                if appearance.customBackgroundImage != nil {
                                    Button("Remove", role: .destructive) {
                                        appearance.clearCustomPhoto()
                                    }
                                    .font(.subheadline.weight(.medium))
                                }
                            }

                            Slider(value: $appearance.backgroundDim, in: 0.15...0.85)
                            Text("Background dim")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: photoItem) { _, item in
                            Task { @MainActor in
                                guard let item,
                                      let data = try? await item.loadTransferable(type: Data.self),
                                      let image = UIImage(data: data) else { return }
                                appearance.setCustomPhoto(image)
                            }
                        }
                    }
                }

                settingsSection("GameHub") {
                    menuRow("Home layout", icon: "square.grid.2x2", value: appearance.hubLayout.title) {
                        ForEach(HubHomeLayout.allCases, id: \.self) { option in
                            Button(option.title) { appearance.hubLayout = option }
                        }
                    }
                    divider
                    menuRow("Game cards", icon: "rectangle.portrait", value: appearance.cardStyle.title) {
                        ForEach(GameCardStyle.allCases, id: \.self) { option in
                            Button(option.title) { appearance.cardStyle = option }
                        }
                    }
                    divider
                    menuRow("Density", icon: "line.3.horizontal", value: appearance.density.title) {
                        ForEach(LibraryDensity.allCases, id: \.self) { option in
                            Button(option.title) { appearance.density = option }
                        }
                    }
                    divider
                    toggleRow("Activity on Home", icon: "chart.bar.xaxis", isOn: $appearance.showActivityOnHome)
                    divider
                    toggleRow("Genre filters", icon: "line.3.horizontal.decrease", isOn: $appearance.showGenreFilters)
                }

                settingsSection("Playback") {
                    settingRow(icon: "play.circle", title: "Continue") {
                        if let game = session.continueGame {
                            Text(game.title)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("No recent game")
                                .foregroundStyle(.secondary)
                        }
                    }
                    divider
                    toggleRow("Resume on launch", icon: "arrow.clockwise", isOn: $resumeOnOpen)
                        .onChange(of: resumeOnOpen) { _, value in session.resumeLastOnOpen = value }
                    divider
                    toggleRow("Keep screen awake", icon: "sun.max", isOn: $keepAwake)
                        .onChange(of: keepAwake) { _, value in session.keepScreenAwake = value }

                    if session.continueGame != nil {
                        divider
                        Button {
                            _ = session.resumeLastStream()
                        } label: {
                            HStack {
                                Label("Resume last game", systemImage: "play.fill")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                settingsSection("Streaming") {
                    menuRow("Resolution", icon: "rectangle.inset.filled", value: resolution) {
                        ForEach(resolutions, id: \.self) { option in
                            Button(option) {
                                resolution = option
                                session.applyStreamResolution(option)
                            }
                        }
                    }
                    divider
                    menuRow("Region", icon: "globe", value: region) {
                        ForEach(regions, id: \.self) { option in
                            Button(option) {
                                region = option
                                session.applyServerRegion(option)
                            }
                        }
                    }
                }

                settingsSection("Controller") {
                    settingRow(
                        icon: controller.isConnected ? "gamecontroller.fill" : "gamecontroller",
                        title: "Status"
                    ) {
                        Text(controller.isConnected ? "Connected" : "Not connected")
                            .foregroundStyle(controller.isConnected ? .green : .secondary)
                    }
                    divider
                    toggleRow("Haptics", icon: "waveform.path", isOn: $appearance.controllerHapticsEnabled)
                    divider
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Rumble intensity", systemImage: "dot.radiowaves.left.and.right")
                                .font(.subheadline)
                            Spacer()
                            Text(rumbleIntensityLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $appearance.controllerRumbleIntensity, in: 0.5...3.0, step: 0.1)
                    }
                    divider
                    Button {
                        ControllerManager.shared.start()
                        ControllerRumble.shared.playTest()
                        testPulseNote = controller.isConnected
                            ? "Test pulse sent."
                            : "Pulse sent. Wake the controller and try again if needed."
                    } label: {
                        HStack {
                            Label("Test rumble", systemImage: "waveform.path.ecg")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)

                    if !testPulseNote.isEmpty {
                        Text(testPulseNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }

                settingsSection("Motion & Sound") {
                    menuRow("Motion", icon: "figure.walk.motion", value: appearance.animationIntensity.title) {
                        ForEach(AnimationIntensity.allCases, id: \.self) { option in
                            Button(option.title) { appearance.animationIntensity = option }
                        }
                    }
                    divider
                    menuRow("Effects", icon: "sparkles", value: appearance.effectsMode.title) {
                        ForEach(EffectsMode.allCases, id: \.self) { option in
                            Button(option.title) { appearance.effectsMode = option }
                        }
                    }
                    divider
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("Glass intensity", systemImage: "circle.hexagongrid.fill")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(appearance.glassIntensity * 100))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $appearance.glassIntensity, in: 0.35...1.0)
                    }
                    divider
                    toggleRow("UI sounds", icon: "speaker.wave.2", isOn: $appearance.uiSoundsEnabled)
                }

                settingsSection("Activity") {
                    settingRow(icon: "chart.bar.fill", title: "This week") {
                        Text(PlayActivityStore.format(activity.weekTotal))
                            .foregroundStyle(.secondary)
                    }
                    if let top = activity.mostPlayedThisWeek {
                        divider
                        settingRow(icon: "trophy", title: "Most played") {
                            Text(top.title)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                settingsSection("Maintenance") {
                    Button {
                        HapticManager.tap()
                        session.returnToHub()
                    } label: {
                        actionRow("Open GameHub", icon: "square.grid.2x2.fill")
                    }
                    divider
                    Button {
                        HapticManager.tap()
                        session.clearCache()
                        SoundManager.playSuccess()
                    } label: {
                        actionRow("Clear cache", icon: "trash")
                    }
                    divider
                    Button {
                        HapticManager.tap()
                        session.refreshBetterXCloudScript()
                    } label: {
                        actionRow("Refresh Better xCloud", icon: "arrow.clockwise")
                    }

                    if session.isSignedIn {
                        divider
                        Button(role: .destructive) {
                            session.signOut()
                        } label: {
                            actionRow("Sign Out", icon: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                settingsSection("Diagnostics & Analytics") {
                    Toggle(isOn: Binding(
                        get: { DiagnosticsStore.shared.isOptedIn },
                        set: { DiagnosticsStore.shared.isOptedIn = $0 }
                    )) {
                        Label("Share diagnostics", systemImage: "chart.bar.xaxis")
                    }
                    Text("Opt-in only. Events are sanitized, stored locally, and uploaded asynchronously. Sensitive fields such as passwords, cookies, tokens, search text, and account identifiers are excluded.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if DiagnosticsStore.shared.isOptedIn {
                        HStack {
                            Text("Pending: \(DiagnosticsStore.shared.pendingCount)")
                            Spacer()
                            Text(DiagnosticsStore.shared.lastUploadStatus)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)

                        Button {
                            DiagnosticsStore.shared.flushNow()
                        } label: {
                            Label("Upload now", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)

                        Button(role: .destructive) {
                            DiagnosticsStore.shared.clearQueue()
                        } label: {
                            Label("Clear local queue", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }

                settingsSection("About")
                    settingRow(icon: "info.circle", title: "Version") {
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    divider
                    settingRow(icon: "gamecontroller", title: "Controller") {
                        Text(controller.isConnected ? "Connected" : "Not connected")
                            .foregroundStyle(controller.isConnected ? .green : .secondary)
                    }
                    divider
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GameStream")
                            .font(.headline.weight(.bold))
                        Text("Native GameHub for Xbox Cloud Gaming.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Made with ♥ by Bestin")
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 2)
                        Text("Built for iOS · Better xCloud integrated")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: syncState)
        .onChange(of: isActive) { _, active in
            if active { syncState() }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Tune GameStream to the way you play.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 34)
    }

    private func settingRow<Accessory: View>(
        icon: String,
        title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.subheadline)

            Spacer(minLength: 10)
            accessory()
                .font(.subheadline)
        }
        .frame(minHeight: 44)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Toggle(title, isOn: isOn)
                .font(.subheadline)
        }
        .frame(minHeight: 44)
    }

    private func menuRow<MenuContent: View>(
        _ title: String,
        icon: String,
        value: String,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline)

                Spacer(minLength: 10)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .font(.subheadline.weight(.medium))
    }

    private func syncState() {
        keepAwake = session.keepScreenAwake
        resumeOnOpen = session.resumeLastOnOpen
        resolution = SessionStore.storedResolution
        region = SessionStore.storedRegion
        ControllerManager.shared.start()
    }
}
