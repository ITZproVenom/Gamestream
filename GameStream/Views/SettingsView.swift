import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var activity = PlayActivityStore.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @State private var keepAwake: Bool = false
    @State private var resumeOnOpen: Bool = false
    @State private var resolution: String = SessionStore.storedResolution
    @State private var region: String = SessionStore.storedRegion

    private let resolutions = ["Auto", "720p", "1080p", "1080p HQ"]
    private let regions = ["Auto", "North America", "Europe", "Asia", "Australia"]

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.9"
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 8)

                    section("Account") {
                        Text(session.accountLabel ?? "Not signed in")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }

                    section("Look") {
                        Text("Appearance")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: AppAppearanceMode.allCases.map(\.title), selected: appearance.mode.title) { title in
                            if let mode = AppAppearanceMode.allCases.first(where: { $0.title == title }) {
                                appearance.mode = mode
                            }
                        }
                        Text("Accent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: AccentTheme.allCases.map(\.title), selected: appearance.accent.title) { title in
                            if let theme = AccentTheme.allCases.first(where: { $0.title == title }) {
                                appearance.accent = theme
                            }
                        }
                        Text("Background")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: BackgroundStyle.allCases.map(\.title), selected: appearance.backgroundStyle.title) { title in
                            if let style = BackgroundStyle.allCases.first(where: { $0.title == title }) {
                                appearance.backgroundStyle = style
                            }
                        }
                        Text("Game cards")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: GameCardStyle.allCases.map(\.title), selected: appearance.cardStyle.title) { title in
                            if let style = GameCardStyle.allCases.first(where: { $0.title == title }) {
                                appearance.cardStyle = style
                            }
                        }
                        Text("Library density")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: LibraryDensity.allCases.map(\.title), selected: appearance.density.title) { title in
                            if let density = LibraryDensity.allCases.first(where: { $0.title == title }) {
                                appearance.density = density
                            }
                        }
                        Text("Motion")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: AnimationIntensity.allCases.map(\.title), selected: appearance.animationIntensity.title) { title in
                            if let intensity = AnimationIntensity.allCases.first(where: { $0.title == title }) {
                                appearance.animationIntensity = intensity
                            }
                        }
                        Text("Effects")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: EffectsMode.allCases.map(\.title), selected: appearance.effectsMode.title) { title in
                            if let mode = EffectsMode.allCases.first(where: { $0.title == title }) {
                                appearance.effectsMode = mode
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Glass intensity")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: $appearance.glassIntensity, in: 0.35...1.0)
                        }
                        Toggle("UI sounds", isOn: $appearance.uiSoundsEnabled)
                    }

                    section("Jump back in") {
                        if let last = session.continueGame {
                            Text(last.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        } else {
                            Text("Play a game and Resume will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("Resume last game on launch", isOn: $resumeOnOpen)
                            .onChange(of: resumeOnOpen) { _, value in
                                session.resumeLastOnOpen = value
                            }
                        Toggle("Keep screen awake", isOn: $keepAwake)
                            .onChange(of: keepAwake) { _, value in
                                session.keepScreenAwake = value
                            }
                        if session.continueGame != nil {
                            Button {
                                _ = session.resumeLastStream()
                            } label: {
                                Text(session.continueGame.map { "Resume \($0.title)" } ?? "Resume")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.glassProminent)
                            .accessibilityLabel("Resume last game")
                        }
                    }

                    section("This week") {
                        Text("\(PlayActivityStore.format(activity.weekTotal)) streamed on this device")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let top = activity.mostPlayedThisWeek {
                            Text("Most played: \(top.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }

                    section("Stream") {
                        Text("Applied to Better xCloud and reloads the page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Target resolution")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: resolutions, selected: resolution) { opt in
                            resolution = opt
                            session.applyStreamResolution(opt)
                        }
                        Text("Server region")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chipRow(options: regions, selected: region) { opt in
                            region = opt
                            session.applyServerRegion(opt)
                        }
                    }

                    section("Actions") {
                        Button {
                            session.returnToHub()
                        } label: {
                            Text("Open GameHub")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glassProminent)
                        Button {
                            session.refreshBetterXCloudScript()
                        } label: {
                            Text("Refresh Better xCloud script")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        if session.isSignedIn {
                            Button {
                                session.signOut()
                            } label: {
                                Text("Sign Out")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.glass)
                        }
                    }

                    section("About") {
                        Text("GameStream iOS \(appVersion) — native GameHub and Xbox Cloud client with Better xCloud.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Made with \u{2764}\u{FE0F} by Bestin")
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 6)
                            .accessibilityLabel("Made with heart by Bestin")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            keepAwake = session.keepScreenAwake
            resumeOnOpen = session.resumeLastOnOpen
            resolution = SessionStore.storedResolution
            region = SessionStore.storedRegion
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func chipRow(options: [String], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    Button {
                        onSelect(opt)
                    } label: {
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
