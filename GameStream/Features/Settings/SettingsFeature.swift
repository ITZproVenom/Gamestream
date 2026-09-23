import SwiftUI
import PhotosUI

struct SettingsFeature: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var activity = PlayActivityStore.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @ObservedObject private var controller = ControllerManager.shared
    @ObservedObject private var diagnostics = DiagnosticsStore.shared
    @State private var keepAwake = false
    @State private var resumeOnOpen = false
    @State private var resolution = SessionStore.storedResolution
    @State private var region = SessionStore.storedRegion
    @State private var photoItem: PhotosPickerItem?
    @State private var testNote = ""

    private let resolutions = ["Auto", "720p", "1080p", "1080p HQ"]
    private let regions = ["Auto", "North America", "Europe", "Asia", "Australia"]

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    }

    private var intensityLabel: String {
        let v = appearance.controllerRumbleIntensity
        if v < 0.85 { return "Light" }
        if v < 1.35 { return "Normal" }
        if v < 2.0 { return "Strong" }
        if v < 2.6 { return "Heavy" }
        return "Max"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .padding(.top, 4)

                section("Account") {
                    Text(session.accountLabel ?? "Not signed in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                section("Controller") {
                    HStack(spacing: 8) {
                        Image(systemName: controller.isConnected ? "gamecontroller.fill" : "gamecontroller")
                            .foregroundStyle(controller.isConnected ? .green : .secondary)
                        Text(controller.isConnected ? "Connected" : "No controller")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Haptics", isOn: $appearance.controllerHapticsEnabled)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Rumble intensity")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(intensityLabel) · \(String(format: "%.1f", appearance.controllerRumbleIntensity))×")
                                .font(.caption.weight(.semibold))
                        }
                        Slider(value: $appearance.controllerRumbleIntensity, in: 0.5...3.0, step: 0.1)
                    }
                    Button {
                        ControllerManager.shared.start()
                        ControllerRumble.shared.playTest()
                        testNote = "Pulse sent — feel two bursts if the pad is awake."
                    } label: {
                        Label("Test rumble", systemImage: "waveform.path")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                    if !testNote.isEmpty {
                        Text(testNote).font(.caption).foregroundStyle(.secondary)
                    }
                }

                section("Appearance") {
                    chips("Theme", AppAppearanceMode.allCases.map(\.title), appearance.mode.title) { t in
                        if let m = AppAppearanceMode.allCases.first(where: { $0.title == t }) { appearance.mode = m }
                    }
                    chips("Accent", AccentTheme.allCases.map(\.title), appearance.accent.title) { t in
                        if let a = AccentTheme.allCases.first(where: { $0.title == t }) { appearance.accent = a }
                    }
                }

                section("Background") {
                    chips("Style", BackgroundStyle.allCases.map(\.title), appearance.backgroundStyle.title) { t in
                        if let s = BackgroundStyle.allCases.first(where: { $0.title == t }) { appearance.backgroundStyle = s }
                    }
                    if appearance.backgroundStyle == .customColor {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(CustomBgColor.allCases) { c in
                                    Circle()
                                        .fill(c.color)
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            if appearance.customBgColor == c {
                                                Circle().strokeBorder(.white, lineWidth: 2.5)
                                            }
                                        }
                                        .onTapGesture { appearance.customBgColor = c }
                                }
                            }
                        }
                    }
                    if appearance.backgroundStyle == .customPhoto {
                        if let img = appearance.customBackgroundImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(appearance.customBackgroundImage == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        if appearance.customBackgroundImage != nil {
                            Button { appearance.clearCustomPhoto() } label: {
                                Text("Remove photo").frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                            .buttonStyle(.glass)
                        }
                        Slider(value: $appearance.backgroundDim, in: 0.15...0.85)
                    }
                }

                section("Library") {
                    chips("Home layout", HubHomeLayout.allCases.map(\.title), appearance.hubLayout.title) { t in
                        if let l = HubHomeLayout.allCases.first(where: { $0.title == t }) { appearance.hubLayout = l }
                    }
                    chips("Cards", GameCardStyle.allCases.map(\.title), appearance.cardStyle.title) { t in
                        if let s = GameCardStyle.allCases.first(where: { $0.title == t }) { appearance.cardStyle = s }
                    }
                    chips("Density", LibraryDensity.allCases.map(\.title), appearance.density.title) { t in
                        if let d = LibraryDensity.allCases.first(where: { $0.title == t }) { appearance.density = d }
                    }
                    Toggle("Activity on home", isOn: $appearance.showActivityOnHome)
                    Toggle("Genre filters", isOn: $appearance.showGenreFilters)
                }

                section("Motion") {
                    chips("Animation", AnimationIntensity.allCases.map(\.title), appearance.animationIntensity.title) { t in
                        if let i = AnimationIntensity.allCases.first(where: { $0.title == t }) { appearance.animationIntensity = i }
                    }
                    chips("Effects", EffectsMode.allCases.map(\.title), appearance.effectsMode.title) { t in
                        if let m = EffectsMode.allCases.first(where: { $0.title == t }) { appearance.effectsMode = m }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Glass intensity").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Slider(value: $appearance.glassIntensity, in: 0.35...1.0)
                    }
                    Toggle("UI sounds", isOn: $appearance.uiSoundsEnabled)
                }

                section("Playback") {
                    if let last = session.continueGame {
                        Text(last.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Toggle("Resume last on launch", isOn: $resumeOnOpen)
                        .onChange(of: resumeOnOpen) { _, v in session.resumeLastOnOpen = v }
                    Toggle("Keep screen awake", isOn: $keepAwake)
                        .onChange(of: keepAwake) { _, v in session.keepScreenAwake = v }
                    if session.continueGame != nil {
                        Button { _ = session.resumeLastStream() } label: {
                            Text(session.continueGame.map { "Resume \($0.title)" } ?? "Resume")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }

                section("This week") {
                    Text("\(PlayActivityStore.format(activity.weekTotal)) streamed")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let top = activity.mostPlayedThisWeek {
                        Text("Most played: \(top.title)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                section("Stream") {
                    Text("Applied via Better xCloud.")
                        .font(.caption).foregroundStyle(.secondary)
                    chips("Resolution", resolutions, resolution) { opt in
                        resolution = opt
                        session.applyStreamResolution(opt)
                    }
                    chips("Region", regions, region) { opt in
                        region = opt
                        session.applyServerRegion(opt)
                    }
                }

                section("Actions") {
                    Button { session.returnToHub() } label: {
                        Text("Open Home")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                    }
                    .buttonStyle(.glassProminent)
                    Button { session.clearCache(); SoundManager.playSuccess() } label: {
                        Text("Clear cache").frame(maxWidth: .infinity).padding(.vertical, 11)
                    }
                    .buttonStyle(.glass)
                    Button { session.refreshBetterXCloudScript() } label: {
                        Text("Refresh Better xCloud").frame(maxWidth: .infinity).padding(.vertical, 11)
                    }
                    .buttonStyle(.glass)
                    if session.isSignedIn {
                        Button { session.signOut() } label: {
                            Text("Sign Out").frame(maxWidth: .infinity).padding(.vertical, 11)
                        }
                        .buttonStyle(.glass)
                    }
                }

                section("Diagnostics & Analytics") {
                    Toggle("Share diagnostics", isOn: $diagnostics.isOptedIn)
                    Text("Opt-in only. Queues sanitized events locally and uploads asynchronously. Never includes passwords, cookies, auth tokens, page HTML, or search queries.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if diagnostics.isOptedIn {
                        HStack {
                            Text("Pending: \(diagnostics.pendingCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !diagnostics.lastUploadStatus.isEmpty {
                                Text(diagnostics.lastUploadStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            diagnostics.flushNow()
                        } label: {
                            Text("Upload now")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        Button {
                            diagnostics.clearQueue()
                        } label: {
                            Text("Clear queue")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                    }
                }

                section("About") {
                    Text("GameStream \(appVersion) — Liquid Glass · Xbox Cloud · Better xCloud")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Made with ♥ by Bestin")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                    Text("Auth & stream core unchanged. UI rebuilt under Features.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .onAppear { syncLocal() }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                appearance.setCustomPhoto(image)
            }
        }
    }

    private func syncLocal() {
        keepAwake = session.keepScreenAwake
        resumeOnOpen = session.resumeLastOnOpen
        resolution = SessionStore.storedResolution
        region = SessionStore.storedRegion
        ControllerManager.shared.start()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func chips(_ label: String, _ options: [String], _ selected: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { opt in
                        Button { onSelect(opt) } label: {
                            Text(opt)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .modifier(FeatureChipStyle(selected: selected == opt))
                    }
                }
            }
        }
    }
}
