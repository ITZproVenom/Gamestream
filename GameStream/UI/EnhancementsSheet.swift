import SwiftUI

/// The app's own stream settings, shown over the game.
///
/// Better xCloud draws its own menu, and for a long time the app tried to
/// dress that menu up: rules for its panels, its dropdowns, its buttons,
/// and a script that opened a tab in it. It never settled, because the
/// menu is not the app's - the script rebuilds it whenever it likes,
/// writes its own stylesheet over the app's, and throws its own failure
/// screen over the page if it is started at the wrong moment.
///
/// So the app stopped touching it. This panel is the app's own: the
/// settings it actually owns, in the app's own style, with the page left
/// alone. Better xCloud is still there doing what only it can do.
struct EnhancementsSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stream: StreamCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Picture") {
                    Picker("Quality", selection: $settings.quality) {
                        ForEach(AppSettings.Quality.allCases, id: \.self) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    Stepper("Sharpness: \(settings.sharpness)",
                            value: $settings.sharpness, in: 0...100)
                    Stepper("Saturation: \(settings.saturation)",
                            value: $settings.saturation, in: 0...100)
                    Stepper("Contrast: \(settings.contrast)",
                            value: $settings.contrast, in: 0...100)
                }

                Section("Session") {
                    Toggle("Prefer H.265 when offered", isOn: $settings.preferHEVC)
                    Toggle("GameStream enhancements", isOn: $settings.enhancerEnabled)
                    Picker("Touch controls", selection: $settings.touchControls) {
                        ForEach(AppSettings.TouchControls.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section("Sound") {
                    Toggle("Rumble", isOn: $settings.rumbleEnabled)
                    if settings.rumbleEnabled {
                        Slider(value: $settings.rumbleIntensity, in: 0.5...3.0, step: 0.1) {
                            Text("Rumble intensity")
                        }
                    }
                }

                Section("While playing") {
                    Toggle("Start the game automatically", isOn: $settings.autoStart)
                    Toggle("Show Xbox's page while the game starts",
                           isOn: $settings.showSiteWhileConnecting)
                    Toggle("Open the statistics panel with the stream",
                           isOn: $settings.showStreamStats)
                    Toggle("Keep the screen awake", isOn: $settings.keepAwake)
                }

                if !stream.offeredCodecs.isEmpty {
                    Section("This session") {
                        LabeledContent("Codecs on offer", value: stream.offeredCodecs)
                    }
                }
            }
            .navigationTitle("Stream settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
