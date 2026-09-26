import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var activity = PlayActivityStore.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @ObservedObject private var controller = ControllerManager.shared
    @State private var keepAwake: Bool = false
    @State private var resumeOnOpen: Bool = false
    @State private var resolution: String = SessionStore.storedResolution
    @State private var region: String = SessionStore.storedRegion
    @State private var photoItem: PhotosPickerItem?
    @State private var testPulseNote: String = ""

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
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 8)

                category("Account") {
                    Text(session.accountLabel ?? "Not signed in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // MARK: Controller test — always visible, never locked behind detection
                category("Controller test") {
                    HStack(spacing: 8) {
                        Image(systemName: controller.isConnected ? "gamecontroller.fill" : "gamecontroller")
                            .foregroundStyle(controller.isConnected ? .green : .secondary)
                        Text(controller.isConnected ? "Controller detected" : "No controller detected yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Controller haptics", isOn: $appearance.controllerHapticsEnabled)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Rumble intensity")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(rumbleIntensityLabel) · \(String(format: "%.1f", appearance.controllerRumbleIntensity))×")
                                .font(.caption.weight(.semibold))
                        }
                        Slider(value: $appearance.controllerRumbleIntensity, in: 0.5...3.0, step: 0.1)
                        Text("Turn intensity up for weak wired pads. Hardware still sets the ceiling.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        ControllerManager.shared.start()
                        ControllerRumble.shared.playTest()
                        testPulseNote = controller.isConnected
                            ? "Pulse sent — you should feel two bursts."
                            : "Pulse sent. If you feel nothing, plug in / wake the pad and try again."
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.path")
                            Text("Test rumble")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)

                    if !testPulseNote.isEmpty {
                        Text(testPulseNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                category("Appearance") {
                    labeledChips("Theme", AppAppearanceMode.allCases.map(\.title), appearance.mode.title) { title in
                        if let m = AppAppearanceMode.allCases.first(where: { $0.title == title }) {
                            appearance.mode = m
                        }
                    }
                    labeledChips("Accent", AccentTheme.allCases.map(\.title), appearance.accent.title) { title in
                        if let t = AccentTheme.allCases.first(where: { $0.title == title }) {
                            appearance.accent = t
                        }
                    }
                }

                category("Background") {
                    labeledChips("Style", BackgroundStyle.allCases.map(\.title), appearance.backgroundStyle.title) { title in
                        if let s = BackgroundStyle.allCases.first(where: { $0.title == title }) {
                            appearance.backgroundStyle = s
                        }
                    }

                    if appearance.backgroundStyle == .customColor {
                        labeledChips("Color", CustomBgColor.allCases.map(\.title), appearance.customBgColor.title) { title in
                            if let c = CustomBgColor.allCases.first(where: { $0.title == title }) {
                                appearance.customBgColor = c
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(CustomBgColor.allCases) { c in
                                    Circle()
                                        .fill(c.color)
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if appearance.customBgColor == c {
                                                Circle().strokeBorder(.white, lineWidth: 2)
                                            }
                                        }
                                        .onTapGesture { appearance.customBgColor = c }
                                }
                            }
                        }
                    }

                    if appearance.backgroundStyle == .customPhoto {
                        VStack(alignment: .leading, spacing: 10) {
                            if let img = appearance.customBackgroundImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(
                                    appearance.customBackgroundImage == nil ? "Choose photo" : "Change photo",
                                    systemImage: "photo"
                                )
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.glass)
                            if appearance.customBackgroundImage != nil {
                                Button {
                                    appearance.clearCustomPhoto()
                                } label: {
                                    Text("Remove photo")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.glass)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Dim overlay")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Slider(value: $appearance.backgroundDim, in: 0.15...0.85)
                            }
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

                    Text("Aurora · Still · Solid · Mesh · Dusk · Midnight, or pick a custom color / photo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                category("Library") {
                    labeledChips("Home layout", HubHomeLayout.allCases.map(\.title), appearance.hubLayout.title) { title in
                        if let l = HubHomeLayout.allCases.first(where: { $0.title == title }) {
                            appearance.hubLayout = l
                        }
                    }
                    labeledChips("Game cards", GameCardStyle.allCases.map(\.title), appearance.cardStyle.title) { title in
                        if let s = GameCardStyle.allCases.first(where: { $0.title == title }) {
                            appearance.cardStyle = s
                        }
                    }
                    labeledChips("Density", LibraryDensity.allCases.map(\.title), appearance.density.title) { title in
                        if let d = LibraryDensity.allCases.first(where: { $0.title == title }) {
                            appearance.density = d
                        }
                    }
                    Toggle("Activity on home", isOn: $appearance.showActivityOnHome)
                    Toggle("Genre filter row", isOn: $appearance.showGenreFilters)
                }

                category("Motion & effects") {
                    labeledChips("Motion", AnimationIntensity.allCases.map(\.title), appearance.animationIntensity.title) { title in
                        if let i = AnimationIntensity.allCases.first(where: { $0.title == title }) {
                            appearance.animationIntensity = i
                        }
                    }
                    labeledChips("Effects", EffectsMode.allCases.map(\.title), appearance.effectsMode.title) { title in
                        if let m = EffectsMode.allCases.first(where: { $0.title == title }) {
                            appearance.effectsMode = m
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Glass intensity")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Slider(value: $appearance.glassIntensity, in: 0.35...1.0)
                    }
                }

                category("Sound") {
                    Toggle("UI sounds", isOn: $appearance.uiSoundsEnabled)
                }

                category("Playback") {
                    if let last = session.continueGame {
                        Text(last.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Play a game and Resume will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Resume last game on launch", isOn: $resumeOnOpen)
                        .onChange(of: resumeOnOpen) { _, value in session.resumeLastOnOpen = value }
                    Toggle("Keep screen awake", isOn: $keepAwake)
                        .onChange(of: keepAwake) { _, value in session.keepScreenAwake = value }
                    if session.continueGame != nil {
                        Button {
                            _ = session.resumeLastStream()
                        } label: {
                            Text(session.continueGame.map { "Resume \($0.title)" } ?? "Resume")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }

                category("This week") {
                    Text("\(PlayActivityStore.format(activity.weekTotal)) streamed on this device")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let top = activity.mostPlayedThisWeek {
                        Text("Most played: \(top.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                category("Stream") {
                    Text("Applied to Better xCloud and reloads the page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    labeledChips("Resolution", resolutions, resolution) { opt in
                        resolution = opt
                        session.applyStreamResolution(opt)
                    }
                    labeledChips("Region", regions, region) { opt in
                        region = opt
                        session.applyServerRegion(opt)
                    }
                }

                category("Actions") {
                    Button {
                        HapticManager.tap()
                        session.returnToHub()
                    } label: {
                        Text("Open GameHub")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        HapticManager.tap()
                        session.clearCache()
                        SoundManager.playSuccess()
                    } label: {
                        Text("Clear cache")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    Button {
                        HapticManager.tap()
                        session.refreshBetterXCloudScript()
                    } label: {
                        Text("Refresh Better xCloud script")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    if session.isSignedIn {
                        Button { session.signOut() } label: {
                            Text("Sign Out")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                    }
                }

                category("About") {
                    Text("GameStream iOS \(appVersion) — native GameHub and Xbox Cloud client with Better xCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Image(systemName: controller.isConnected ? "gamecontroller.fill" : "gamecontroller")
                            .foregroundStyle(controller.isConnected ? .green : .secondary)
                        Text(controller.isConnected ? "Controller connected" : "No controller")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Made with \u{2665} by Bestin")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .safeAreaPadding(.top, 12)
        .safeAreaPadding(.bottom, 92)
        .scrollIndicators(.hidden)
        .onAppear {
            keepAwake = session.keepScreenAwake
            resumeOnOpen = session.resumeLastOnOpen
            resolution = SessionStore.storedResolution
            region = SessionStore.storedRegion
            ControllerManager.shared.start()
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            keepAwake = session.keepScreenAwake
            resumeOnOpen = session.resumeLastOnOpen
            resolution = SessionStore.storedResolution
            region = SessionStore.storedRegion
            ControllerManager.shared.start()
        }
    }

    private func category<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func labeledChips(_ label: String, _ options: [String], _ selected: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { opt in
                        Button { onSelect(opt) } label: {
                            Text(opt)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .modifier(HubChipStyle(selected: selected == opt))
                        .accessibilityLabel(opt)
                    }
                }
            }
        }
    }
}
